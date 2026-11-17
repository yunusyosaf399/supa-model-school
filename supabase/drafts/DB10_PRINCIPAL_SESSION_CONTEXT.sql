-- DB10 Principal login context; never accepts a client-supplied actor.
-- Only independently authenticated, confirmed, active campus Principals.
create or replace function app_private.principal_session_context()
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_school_id uuid;
  v_school_name text;
  v_display_name text;
  v_campuses jsonb;
  v_count integer;
begin
  if v_actor is null then
    raise exception 'Principal authentication required' using errcode='42501';
  end if;

  select count(distinct r.school_id) into v_count
  from public.user_roles r
  join public.user_profiles p on p.user_id=r.user_id and p.is_active
  join auth.users u on u.id=r.user_id
  join public.schools s on s.id=r.school_id and s.status='active'
  join public.campuses c on c.id=r.campus_id
    and c.school_id=r.school_id and c.is_active
  where r.user_id=v_actor and r.role='principal' and r.is_active
    and u.email_confirmed_at is not null and u.deleted_at is null
    and u.is_anonymous is not true
    and not exists(
      select 1 from public.user_roles x
      where x.user_id=v_actor and x.school_id=r.school_id
        and x.is_active and x.role in ('owner','super_admin')
    );
  if v_count<>1 then
    raise exception 'One active school Principal membership is required'
      using errcode='42501';
  end if;

  select r.school_id,s.name,p.display_name,
    coalesce(jsonb_agg(distinct jsonb_build_object(
      'id',c.id,'name',c.name
    )),'[]'::jsonb)
  into v_school_id,v_school_name,v_display_name,v_campuses
  from public.user_roles r
  join public.user_profiles p on p.user_id=r.user_id and p.is_active
  join auth.users u on u.id=r.user_id
  join public.schools s on s.id=r.school_id and s.status='active'
  join public.campuses c on c.id=r.campus_id
    and c.school_id=r.school_id and c.is_active
  where r.user_id=v_actor and r.role='principal' and r.is_active
    and u.email_confirmed_at is not null and u.deleted_at is null
    and u.is_anonymous is not true
    and not exists(
      select 1 from public.user_roles x
      where x.user_id=v_actor and x.school_id=r.school_id
        and x.is_active and x.role in ('owner','super_admin')
    )
  group by r.school_id,s.name,p.display_name;

  if v_school_id is null or jsonb_array_length(v_campuses)=0 then
    raise exception 'No assigned Principal campus' using errcode='42501';
  end if;
  return jsonb_build_object('user_id',v_actor,'school_id',v_school_id,
     'school_name',v_school_name,'display_name',v_display_name,
     'campuses',v_campuses);
end;
$fn$;

create or replace function public.principal_session_context()
returns jsonb language sql stable security invoker set search_path=''
as $fn$
  select app_private.principal_session_context();
$fn$;

revoke all on function app_private.principal_session_context()
  from public,anon,authenticated;
revoke all on function public.principal_session_context()
  from public,anon,authenticated;
grant execute on function app_private.principal_session_context()
  to authenticated;
grant execute on function public.principal_session_context()
  to authenticated;
