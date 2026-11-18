-- DB16: Real, assigned-campus Principal dashboard matching Owner styling.
-- Principal default dashboard grant is revocable by the Owner. Preserve explicit false.
-- No Owner RPC access, no demo fixtures, no raw table permissions.
create or replace function app_private.sms_permission_allowed(
 p_school uuid,p_campus uuid,p_code text)
returns boolean language sql stable security definer set search_path=''
as $fn$
 select (select auth.uid()) is not null and exists(
 select 1 from public.user_roles r
 join public.user_profiles up on up.user_id=r.user_id
 join auth.users u on u.id=r.user_id
 join public.schools s on s.id=r.school_id
 join public.campuses c on c.id=r.campus_id and c.school_id=r.school_id
 left join app_private.sms_staff_grants g on g.role_id=r.id and g.code=p_code
 where r.user_id=(select auth.uid()) and r.school_id=p_school and
   r.campus_id=p_campus and r.is_active and r.role not in ('owner','super_admin')
   and up.is_active and u.email_confirmed_at is not null
   and u.deleted_at is null and u.is_anonymous is not true
   and s.status='active' and c.is_active
   and coalesce(g.allowed,(r.role='principal' and p_code in ('admissions.review','dashboard.read')))
 );
$fn$;

create or replace function app_private.owner_staff_permission_matrix(p_role_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_role public.user_roles%rowtype;v_data jsonb;
begin
 select * into v_role from public.user_roles where id=p_role_id;
 if not found or v_role.role in ('owner','super_admin')
  or not app_private.is_verified_school_owner((select auth.uid()),v_role.school_id)
 then raise exception 'Owner staff permissions access denied' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object(
  'code',c.code,'section',c.section,'title',c.title,'action',c.action,
  'implemented',c.is_implemented,
  'allowed',coalesce(g.allowed,(v_role.role='principal' and c.code in ('admissions.review','dashboard.read')))
 ) order by c.section,c.action,c.code),'[]'::jsonb) into v_data
 from app_private.sms_permission_catalog c
 left join app_private.sms_staff_grants g on g.role_id=p_role_id and g.code=c.code;
 return v_data;
end;
$fn$;

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
     'logo_storage_path',(select s.logo_storage_path from public.schools s where s.id=v_school_id),
     'campuses',v_campuses);
end;
$fn$;

update app_private.sms_permission_catalog
set is_implemented=true where code in ('dashboard.read','students.read');


create or replace function app_private.principal_dashboard_snapshot(
  p_school_id uuid,p_campus_id uuid
) returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare
  v_actor uuid:=(select auth.uid());
  v_school public.schools%rowtype;
  v_campus public.campuses%rowtype;
  v_year public.academic_years%rowtype;
  v_students bigint;
  v_pending bigint;
  v_recent jsonb:='[]'::jsonb;
begin
  -- A dashboard permission is not a license to enter another campus.
  -- Enforce BOTH current verified Principal membership and explicit grant.
  if p_school_id is null or p_campus_id is null or v_actor is null
     or not exists(
        select 1 from public.user_roles r
        join public.user_profiles up on up.user_id=r.user_id and up.is_active
        join auth.users u on u.id=r.user_id
        join public.schools s on s.id=r.school_id and s.status='active'
        join public.campuses c on c.id=r.campus_id
          and c.school_id=r.school_id and c.is_active
        where r.user_id=v_actor and r.school_id=p_school_id
          and r.campus_id=p_campus_id and r.role='principal' and r.is_active
          and u.email_confirmed_at is not null and u.deleted_at is null
          and u.is_anonymous is not true
          and not exists(select 1 from public.user_roles own
            where own.user_id=v_actor and own.school_id=p_school_id
              and own.is_active and own.role in ('owner','super_admin'))
     )
     or not app_private.sms_permission_allowed(
       p_school_id,p_campus_id,'dashboard.read')
  then raise exception 'Assigned Principal dashboard permission required'
    using errcode='42501'; end if;

  select * into v_school from public.schools
  where id=p_school_id and status='active';
  select * into v_campus from public.campuses
  where id=p_campus_id and school_id=p_school_id and is_active;
  if v_school.id is null or v_campus.id is null then
    raise exception 'School or campus no longer active' using errcode='42501';
  end if;
  select * into v_year from public.academic_years
  where school_id=p_school_id and is_active
  order by starts_on desc,id limit 1;

  -- Dashboard permission exposes only aggregate pupil counts, never PII.
  if v_year.id is not null then
    select count(distinct e.student_id) into v_students
    from public.student_enrollments e
    join public.students st on st.id=e.student_id and st.school_id=e.school_id
    where e.school_id=p_school_id and e.campus_id=p_campus_id
      and e.academic_year_id=v_year.id
      and e.ended_on is null and st.active_status='active';

    if app_private.sms_permission_allowed(
      p_school_id,p_campus_id,'admissions.review') then
      select count(*) into v_pending
      from public.admission_applications a
      where a.school_id=p_school_id and a.campus_id=p_campus_id
        and a.academic_year_id=v_year.id
        and a.admission_status='submitted' and a.approval_state='pending'
        and a.created_by is distinct from v_actor;
    end if;

    -- Names and classes only if this account has explicit records access.
    if app_private.sms_permission_allowed(
      p_school_id,p_campus_id,'students.read') then
      select coalesce(jsonb_agg(jsonb_build_object(
        'name',q.applicant_name,'class',q.class_name,
        'when',q.approved_date)), '[]'::jsonb) into v_recent
      from (
        select a.applicant_name,coalesce(c.name,'Unassigned') class_name,
          coalesce(a.approved_at::date::text,'') approved_date
        from public.admission_applications a
        left join public.classes c on c.id=a.requested_class_id
          and c.school_id=a.school_id and c.campus_id=a.campus_id
        where a.school_id=p_school_id and a.campus_id=p_campus_id
          and a.academic_year_id=v_year.id
          and a.admission_status='approved'
        order by a.approved_at desc nulls last,a.id
        limit 4
      ) q;
    end if;
  end if;

  -- No demo snapshots, fee balances, personal contacts, or synthetic counts.
  return jsonb_build_object(
    'is_demo',false,'source','live_principal_campus_summary',
    'school_name',v_school.name,'campus_name',v_campus.name,
    'year_label',coalesce(v_year.label,'Not configured'),
    'currency_code',v_school.currency_code,
    'active_students',v_students,
    'fee_collected',null,'fees_outstanding',null,
    'attendance_present',null,'attendance_total',null,
    'fee_trend','[]'::jsonb,'recent_admissions',v_recent,
    'pending_admissions',v_pending,
    'pending_expenses',null,'pending_leave',null,
    'sync_status','Not configured'
  );
end;
$fn$;

create or replace function public.principal_dashboard_snapshot(
  p_school_id uuid,p_campus_id uuid
) returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.principal_dashboard_snapshot(
  p_school_id,p_campus_id); $fn$;
revoke all on function app_private.principal_dashboard_snapshot(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.principal_dashboard_snapshot(uuid,uuid)
  from public,anon,authenticated;
grant execute on function app_private.principal_dashboard_snapshot(uuid,uuid)
  to authenticated;
grant execute on function public.principal_dashboard_snapshot(uuid,uuid)
  to authenticated;
