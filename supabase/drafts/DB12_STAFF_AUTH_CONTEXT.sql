-- DB12 staff login context. Other staff roles receive an account/security
-- screen only until each role-specific school workspace is implemented.
create or replace function app_private.staff_session_context()
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
 v_actor uuid:=(select auth.uid());
 v_count bigint;
 v_data jsonb;
begin
 if v_actor is null then
  raise exception 'Verified staff login required' using errcode='42501';
 end if;
 select count(*) into v_count
 from public.user_roles r
 join public.user_profiles p on p.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 join public.schools s on s.id=r.school_id
 join public.campuses c on c.id=r.campus_id and c.school_id=s.id
 where r.user_id=v_actor and r.is_active
 and r.role not in ('owner','super_admin','principal')
 and p.is_active and s.status='active' and c.is_active
 and u.email_confirmed_at is not null and u.deleted_at is null
 and u.is_anonymous is not true
 and not exists(select 1 from public.user_roles x
   where x.user_id=v_actor and x.is_active
    and x.role in ('owner','super_admin','principal'));
 if v_count<>1 then
  raise exception 'One active staff role required' using errcode='42501';
 end if;
 select jsonb_build_object(
    'user_id',r.user_id,'school_id',s.id,'school_name',s.name,
    'campus_id',c.id,'campus_name',c.name,
    'display_name',p.display_name,'role',r.role)
 into v_data
 from public.user_roles r
 join public.user_profiles p on p.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 join public.schools s on s.id=r.school_id
 join public.campuses c on c.id=r.campus_id and c.school_id=s.id
 where r.user_id=v_actor and r.is_active
 and r.role not in ('owner','super_admin','principal')
 and p.is_active and s.status='active' and c.is_active
 and u.email_confirmed_at is not null and u.deleted_at is null
 and u.is_anonymous is not true;
 return v_data;
end;
$fn$;

create or replace function public.staff_session_context()
returns jsonb language sql stable security invoker set search_path=''
as $fn$
 select app_private.staff_session_context();
$fn$;

revoke all on function app_private.staff_session_context()
 from public,anon,authenticated;
revoke all on function public.staff_session_context()
 from public,anon,authenticated;
grant execute on function app_private.staff_session_context()
 to authenticated;
grant execute on function public.staff_session_context()
 to authenticated;
