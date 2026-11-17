-- DB12: Owners create credentialed staff directly; invitation is disabled.
-- Auth credentials are created only by Supabase Admin inside the Edge Function.
alter table app_private.owner_user_admin_events
 drop constraint if exists owner_user_admin_events_action_check;
alter table app_private.owner_user_admin_events
 add constraint owner_user_admin_events_action_check
 check (action in ('invite','create','activate','deactivate'));

create or replace function app_private.owner_register_created_user(
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
 then raise exception 'Invalid created user details' using errcode='22023';
 end if;
 if not exists (select 1 from auth.users u
  where u.id=p_target and lower(u.email)=lower(btrim(p_expected_email))
    and u.deleted_at is null and u.is_anonymous is not true
    and u.email_confirmed_at is not null
    and u.last_sign_in_at is null
    and u.created_at >= now() - interval '10 minutes'
    and u.invited_at is null) then
  raise exception 'Created Auth identity does not match'
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
 values(p_school,p_actor,p_target,v_role_id,'create',p_role,p_campus);
 return jsonb_build_object('role_id',v_role_id,'user_id',p_target,
   'status','created','role',p_role);
end;
$fn$;



-- Staff account creation only from the trusted Edge server.
create or replace function public.server_register_created_user(
 p_actor uuid,p_target uuid,p_school uuid,p_campus uuid,
 p_role text,p_display_name text,p_expected_email text
) returns jsonb language sql security invoker set search_path=''
as $fn$
 select app_private.owner_register_created_user(
   p_actor,p_target,p_school,p_campus,p_role,p_display_name,p_expected_email);
$fn$;

-- Disable legacy invite role assignment so an old Edge bundle
-- cannot provision school roles via emailed invitations.
revoke all on function public.server_register_invited_user(
 uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
revoke all on function app_private.owner_register_invited_user(
 uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;

revoke all on function app_private.owner_register_created_user(
 uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
revoke all on function public.server_register_created_user(
 uuid,uuid,uuid,uuid,text,text,text) from public,anon,authenticated,service_role;
grant execute on function app_private.owner_register_created_user(
 uuid,uuid,uuid,uuid,text,text,text) to service_role;
grant execute on function public.server_register_created_user(
 uuid,uuid,uuid,uuid,text,text,text) to service_role;
