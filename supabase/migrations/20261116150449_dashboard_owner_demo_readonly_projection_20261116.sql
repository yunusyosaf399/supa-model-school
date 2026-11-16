-- Exact schema migration applied to hosted Supabase (20261116150449).
-- Dashboard read projection + isolated demonstration fixtures.
-- No DB02 student, fee, attendance or admissions records are seeded.
-- The single-school Owner initial setup is NOT changed.
--
-- IMPORTANT: This table lives inside the non-Data-API app_private schema.
-- All demo metrics are tagged and excluded automatically once real Owner
-- setup is complete. Owner reads go through a checked read-only RPC.

create table app_private.dashboard_demo_snapshots (
  school_id uuid not null references public.schools(id) on delete cascade,
  campus_id uuid not null,
  snapshot jsonb not null check (jsonb_typeof(snapshot)='object'
    and snapshot->>'is_demo' = 'true'),
  created_at timestamptz not null default now(),
  primary key (school_id,campus_id),
  foreign key (campus_id,school_id)
    references public.campuses(id,school_id) on delete cascade
);
alter table app_private.dashboard_demo_snapshots enable row level security;
revoke all on app_private.dashboard_demo_snapshots from public,anon,authenticated;

create or replace function app_private.owner_dashboard_snapshot(
  p_school_id uuid, p_campus_id uuid
)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_user uuid := (select auth.uid());
  v_school public.schools%rowtype;
  v_campus public.campuses%rowtype;
  v_year public.academic_years%rowtype;
  v_setup boolean;
  v_demo jsonb;
  v_students bigint := 0;
  v_pending bigint := 0;
  v_recent jsonb := '[]'::jsonb;
begin
  if v_user is null or p_school_id is null or p_campus_id is null
     or not exists (
       select 1 from public.user_roles r
       join public.user_profiles p on p.user_id=r.user_id
       join auth.users u on u.id=r.user_id
       where r.user_id=v_user
         and r.school_id=p_school_id
         and r.campus_id is null
         and r.role='owner'
         and r.is_active and p.is_active
         and u.email_confirmed_at is not null
     )
  then
    raise exception 'Dashboard requires verified school Owner'
      using errcode='42501';
  end if;
  select * into v_school from public.schools
    where id=p_school_id and status='active';
  select * into v_campus from public.campuses
    where id=p_campus_id and school_id=p_school_id and is_active;
  if not found or v_campus.id is null or v_school.id is null then
    raise exception 'Unauthorized or inactive campus' using errcode='42501';
  end if;
  select exists(
    select 1 from public.school_settings st
    where st.school_id=p_school_id and st.setting_key='initial_setup'
      and st.setting_value->>'status'='complete'
  ) into v_setup;
  select * into v_year from public.academic_years
    where school_id=p_school_id and is_active order by starts_on desc limit 1;

  if not v_setup or v_year.id is null then
    select d.snapshot into v_demo
    from app_private.dashboard_demo_snapshots d
    where d.school_id=p_school_id and d.campus_id=p_campus_id;
    return coalesce(v_demo, '{}'::jsonb) || jsonb_build_object(
      'is_demo',true,
      'school_name',v_school.name,
      'campus_name',v_campus.name,
      'year_label',coalesce(v_demo->>'year_label','Not configured'),
      'currency_code',coalesce(v_demo->>'currency_code','PKR'),
      'source','database_test_fixture',
      'sync_status','Not configured'
    );
  end if;

  select count(distinct e.student_id) into v_students
  from public.student_enrollments e
  join public.students st
    on st.id=e.student_id and st.school_id=e.school_id
  where e.school_id=p_school_id and e.campus_id=p_campus_id
    and e.academic_year_id=v_year.id
    and e.ended_on is null and st.active_status='active';

  select count(*) into v_pending from public.admission_applications a
  where a.school_id=p_school_id and a.campus_id=p_campus_id
    and a.academic_year_id=v_year.id
    and a.admission_status='submitted' and a.approval_state='pending';

  select coalesce(jsonb_agg(jsonb_build_object(
      'name',q.applicant_name,
      'class',q.class_name,
      'when',q.admitted_on)), '[]'::jsonb)
  into v_recent
  from (
    select a.applicant_name,
      coalesce(c.name,'Class not assigned') as class_name,
      coalesce(a.approved_at::date::text,'') as admitted_on
    from public.admission_applications a
    left join public.classes c on c.id=a.requested_class_id
      and c.school_id=a.school_id and c.campus_id=a.campus_id
    where a.school_id=p_school_id and a.campus_id=p_campus_id
      and a.academic_year_id=v_year.id
      and a.admission_status='approved'
    order by a.approved_at desc nulls last, a.id
    limit 4
  ) q;

  -- Financial, attendance and sync entities are not deployed yet;
  -- deliberately return NULL rather than inventing live transactions.
  return jsonb_build_object(
    'is_demo',false,
    'source','live_db02_summary',
    'school_name',v_school.name,'campus_name',v_campus.name,
    'year_label',v_year.label,'currency_code',v_school.currency_code,
    'active_students',v_students,
    'fee_collected',null,'fees_outstanding',null,
    'attendance_present',null,'attendance_total',null,
    'fee_trend','[]'::jsonb,
    'recent_admissions',v_recent,
    'pending_admissions',v_pending,
    'pending_expenses',null,'pending_leave',null,
    'sync_status','Not configured'
  );
end;
$$;

revoke all on function app_private.owner_dashboard_snapshot(uuid,uuid)
  from public,anon,authenticated;
grant execute on function app_private.owner_dashboard_snapshot(uuid,uuid)
  to authenticated;

-- Public wrapper is invoker-mode and does not bypass authorization.
create or replace function public.owner_dashboard_snapshot(
  p_school_id uuid,p_campus_id uuid
)
returns jsonb
language sql stable security invoker set search_path = ''
as $$
 select app_private.owner_dashboard_snapshot(p_school_id,p_campus_id)
$$;
revoke all on function public.owner_dashboard_snapshot(uuid,uuid)
  from public,anon,authenticated;
grant execute on function public.owner_dashboard_snapshot(uuid,uuid)
  to authenticated;
