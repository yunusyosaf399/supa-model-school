-- Owner user administration: private authorization gates and scoped RPCs.
-- Auth invitation is performed ONLY in Edge Function with server-side service key.
create table if not exists app_private.owner_user_admin_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id),
  actor_id uuid not null references auth.users(id),
  target_user_id uuid not null references auth.users(id),
  role_id uuid references public.user_roles(id),
  action text not null check (action in ('invite','activate','deactivate')),
  role text not null,
  campus_id uuid not null,
  created_at timestamptz not null default now()
);
alter table app_private.owner_user_admin_events enable row level security;
revoke all on app_private.owner_user_admin_events from public,anon,authenticated;

create or replace function app_private.is_verified_school_owner(p_actor uuid,p_school uuid)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select p_actor is not null and exists(
 select 1 from public.user_roles r
 join public.user_profiles profile on profile.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 join public.schools s on s.id=r.school_id
 where r.user_id=p_actor and r.school_id=p_school and
  r.role='owner' and r.campus_id is null and r.is_active
  and profile.is_active and u.email_confirmed_at is not null
  and u.deleted_at is null and u.is_anonymous is not true
  and s.status='active'
 );
$fn$;

create or replace function app_private.is_allowed_invitation_role(p_role text)
returns boolean language sql immutable set search_path=''
as $fn$
 select p_role in (
 'principal','vice_principal','admin','accountant','hr',
 'teacher','coordinator','librarian','transport_manager','driver',
 'nurse','store_keeper','security_guard','parent','attendance_staff'
 );
$fn$;

-- Authenticated Owner performs eligibility check BEFORE Auth invitation.
create or replace function app_private.owner_user_invite_preflight(
 p_school uuid,p_campus uuid,p_role text)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school) then
  raise exception 'Verified school Owner required' using errcode='42501';end if;
 if not app_private.is_allowed_invitation_role(p_role)
  or not exists(select 1 from public.campuses c where c.id=p_campus
    and c.school_id=p_school and c.is_active) then
  raise exception 'Invalid assigned campus or staff role' using errcode='22023';
 end if;
 return jsonb_build_object('eligible',true);
end;
$fn$;

create or replace function public.owner_user_invite_preflight(
 p_school uuid,p_campus uuid,p_role text)
returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.owner_user_invite_preflight(p_school,p_campus,p_role);
$fn$;

-- This RPC is restricted to service_role; the caller is a trusted Edge
-- Function which obtains p_actor through auth.getUser(Bearer JWT), not from
-- the request JSON. The DB still rechecks Owner and unique school membership.
create or replace function app_private.owner_register_invited_user(
 p_actor uuid,p_target uuid,p_school uuid,p_campus uuid,
 p_role text,p_display_name text,p_expected_email text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_role_id uuid;
begin
 if not app_private.is_verified_school_owner(p_actor,p_school)
   or not app_private.is_allowed_invitation_role(p_role)
   or p_actor=p_target then
  raise exception 'Verified Owner cannot assign this role' using errcode='42501';
 end if;
 if length(btrim(coalesce(p_display_name,''))) not between 2 and 120
   or length(btrim(coalesce(p_expected_email,''))) not between 5 and 254
   or not exists(select 1 from public.campuses c
      where c.id=p_campus and c.school_id=p_school and c.is_active)
 then raise exception 'Invalid invited user details' using errcode='22023';
 end if;
 if not exists (select 1 from auth.users u
  where u.id=p_target and lower(u.email)=lower(btrim(p_expected_email))
    and u.deleted_at is null and u.is_anonymous is not true) then
  raise exception 'Invited Auth identity does not match'
    using errcode='42501';
 end if;
 -- No silent assignment of an existing account to another school.
 if exists(select 1 from public.user_roles r where r.user_id=p_target)
  or exists(select 1 from public.user_profiles p where p.user_id=p_target)
 then raise exception 'This Auth account is already assigned' using errcode='23505';
 end if;
 insert into public.user_profiles(user_id,display_name,is_active)
 values(p_target,btrim(p_display_name),true);
 insert into public.user_roles(
  user_id,school_id,campus_id,role,is_active,created_by)
 values(p_target,p_school,p_campus,p_role,true,p_actor)
 returning id into v_role_id;
 insert into app_private.owner_user_admin_events(
   school_id,actor_id,target_user_id,role_id,action,role,campus_id)
 values(p_school,p_actor,p_target,v_role_id,'invite',p_role,p_campus);
 return jsonb_build_object('role_id',v_role_id,'user_id',p_target,
   'status','invited','role',p_role);
end;
$fn$;

-- Unexposed private schemas cannot be called through PostgREST directly.
-- This public SECURITY INVOKER bridge is callable ONLY by service_role.
create or replace function public.server_register_invited_user(
 p_actor uuid,p_target uuid,p_school uuid,p_campus uuid,
 p_role text,p_display_name text,p_expected_email text)
returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_register_invited_user(
   p_actor,p_target,p_school,p_campus,p_role,p_display_name,p_expected_email);
$fn$;

-- User administration listing contains only staff display name, email, role
-- and assigned campus, not credentials, invitation tokens or auth metadata.
create or replace function app_private.owner_school_users(p_school uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_data jsonb;
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school) then
   raise exception 'Verified Owner required' using errcode='42501';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'role_id',r.id,'user_id',r.user_id,'name',p.display_name,
  'email',u.email,'role',r.role,'campus_id',r.campus_id,
  'campus_name',c.name,'active',r.is_active,
  'email_confirmed',u.email_confirmed_at is not null,
  'created_at',r.created_at
 ) order by r.created_at desc,r.id),'[]'::jsonb) into v_data
 from public.user_roles r
 join public.user_profiles p on p.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 left join public.campuses c on c.id=r.campus_id and c.school_id=r.school_id
 where r.school_id=p_school;
 return v_data;
end;
$fn$;

create or replace function public.owner_school_users(p_school uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.owner_school_users(p_school);
$fn$;

create or replace function app_private.owner_set_staff_active(
 p_role_id uuid,p_active boolean)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_role public.user_roles%rowtype;v_actor uuid:=(select auth.uid());
begin
 select * into v_role from public.user_roles where id=p_role_id for update;
 if not found or not app_private.is_verified_school_owner(v_actor,v_role.school_id)
 or v_role.role in ('owner','super_admin')
 or v_role.user_id=v_actor or p_active is null then
  raise exception 'This school role cannot be changed' using errcode='42501';
 end if;
 if v_role.is_active is distinct from p_active then
  update public.user_roles set is_active=p_active where id=p_role_id;
  insert into app_private.owner_user_admin_events(
    school_id,actor_id,target_user_id,role_id,action,role,campus_id)
  values(v_role.school_id,v_actor,v_role.user_id,v_role.id,
     case when p_active then 'activate' else 'deactivate' end,
     v_role.role,v_role.campus_id);
 end if;
 return jsonb_build_object('role_id',p_role_id,'active',p_active);
end;
$fn$;

create or replace function public.owner_set_staff_active(
 p_role_id uuid,p_active boolean)
returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_set_staff_active(p_role_id,p_active);
$fn$;

revoke all on function app_private.is_verified_school_owner(uuid,uuid)
 from public,anon,authenticated;
revoke all on function app_private.is_allowed_invitation_role(text)
 from public,anon,authenticated;
revoke all on function app_private.owner_user_invite_preflight(uuid,uuid,text)
 from public,anon,authenticated;
revoke all on function public.owner_user_invite_preflight(uuid,uuid,text)
 from public,anon,authenticated;
revoke all on function app_private.owner_register_invited_user(uuid,uuid,uuid,uuid,text,text,text)
 from public,anon,authenticated;
revoke all on function app_private.owner_school_users(uuid)
 from public,anon,authenticated;
revoke all on function public.owner_school_users(uuid)
 from public,anon,authenticated;
revoke all on function app_private.owner_set_staff_active(uuid,boolean)
 from public,anon,authenticated;
revoke all on function public.owner_set_staff_active(uuid,boolean)
 from public,anon,authenticated;
grant execute on function app_private.is_verified_school_owner(uuid,uuid)
 to authenticated,service_role;
grant execute on function app_private.is_allowed_invitation_role(text)
 to authenticated,service_role;
grant execute on function app_private.owner_user_invite_preflight(uuid,uuid,text)
 to authenticated;
grant execute on function public.owner_user_invite_preflight(uuid,uuid,text)
 to authenticated;
grant execute on function app_private.owner_register_invited_user(uuid,uuid,uuid,uuid,text,text,text)
 to service_role;
grant execute on function app_private.owner_school_users(uuid)
 to authenticated;
grant execute on function public.owner_school_users(uuid)
 to authenticated;
grant execute on function app_private.owner_set_staff_active(uuid,boolean)
 to authenticated;
grant execute on function public.owner_set_staff_active(uuid,boolean)
 to authenticated;
revoke all on function public.server_register_invited_user(
 uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.server_register_invited_user(
 uuid,uuid,uuid,uuid,text,text,text) to service_role;
