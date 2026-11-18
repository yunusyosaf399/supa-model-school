-- DB19: Owner-only, read-only Staff Directory and Transport overview.
-- Existing public domain tables remain RLS-protected and not directly
-- selectable by authenticated clients. No writes/payroll/attendance.
create or replace function app_private.owner_staff_directory_snapshot(
  p_school uuid, p_campus uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $func$
declare
  v_staff jsonb;
  v_departments jsonb;
  v_positions jsonb;
begin
  if not app_private.is_verified_school_owner((select auth.uid()),p_school)
   or not exists (
     select 1 from public.campuses c
     where c.id=p_campus and c.school_id=p_school and c.is_active)
  then
    raise exception 'Verified Owner and active school campus required'
      using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,
    'employee_no',e.employee_no,
    'full_name',e.full_name,
    'full_name_ur',e.full_name_ur,
    'hired_on',e.hired_on,
    'employment_type',e.employment_type,
    'employment_status',e.employment_status,
    'linked_login',e.auth_user_id is not null,
    'department',d.name,
    'department_code',d.code,
    'position',p.title,
    'teaching',p.is_teaching_position,
    'starts_on',a.starts_on,
    'assignment_status',a.assignment_status
  ) order by e.employee_no, e.id),'[]'::jsonb)
  into v_staff
  from public.employee_assignments a
  join public.employees e on e.id=a.employee_id and e.school_id=a.school_id
  join public.employee_positions p on p.id=a.position_id
    and p.school_id=a.school_id and p.department_id=a.department_id
  join public.employee_departments d on d.id=a.department_id
    and d.school_id=a.school_id
  where a.school_id=p_school and a.campus_id=p_campus
    and a.ends_on is null and a.assignment_status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'code',d.code,'name',d.name,'active',d.is_active
  ) order by d.name),'[]'::jsonb) into v_departments
  from public.employee_departments d
  where d.school_id=p_school and d.is_active;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'code',p.code,'title',p.title,
    'department_id',p.department_id,
    'is_teaching',p.is_teaching_position
  ) order by p.title),'[]'::jsonb) into v_positions
  from public.employee_positions p
  where p.school_id=p_school and p.is_active;

  return jsonb_build_object(
    'school_id',p_school,
    'campus_id',p_campus,
    'staff',v_staff,
    'departments',v_departments,
    'positions',v_positions,
    'read_only',true
  );
end;
$func$;

create or replace function app_private.owner_transport_directory_snapshot(
  p_school uuid, p_campus uuid, p_year uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $func$
declare
  v_routes jsonb;
  v_vehicles jsonb;
  v_year_label text;
begin
  if not app_private.is_verified_school_owner((select auth.uid()),p_school)
   or not exists (
     select 1 from public.campuses c
     where c.id=p_campus and c.school_id=p_school and c.is_active)
  then
    raise exception 'Verified Owner and active school campus required'
      using errcode='42501';
  end if;
  select y.label into v_year_label from public.academic_years y
  where y.id=p_year and y.school_id=p_school;
  if v_year_label is null then
    raise exception 'Academic year does not belong to school'
      using errcode='42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',v.id,
    'registration_no',v.registration_no,
    'capacity',v.capacity,
    'status',v.status
  ) order by v.registration_no),'[]'::jsonb) into v_vehicles
  from public.transport_vehicles v
  where v.school_id=p_school and v.campus_id=p_campus;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,
    'code',r.route_code,
    'name',r.route_name,
    'active',r.is_active,
    'stops',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',st.id,
        'order',st.stop_order,
        'name',st.stop_name,
        'pickup_time',st.pickup_time,
        'dropoff_time',st.dropoff_time
      ) order by st.stop_order)
      from public.transport_route_stops st
      where st.route_id=r.id and st.school_id=p_school
        and st.campus_id=p_campus
    ),'[]'::jsonb),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,
        'name',s.full_name_en,
        'registration',s.registration_no,
        'class_name',cl.name,
        'section_name',sec.name,
        'stop_id',st.id,
        'stop_name',st.stop_name,
        'starts_on',a.starts_on
      ) order by cl.sort_order,s.full_name_en,s.id)
      from public.transport_student_assignments a
      join public.student_enrollments e
        on e.id=a.enrollment_id and e.student_id=a.student_id
        and e.school_id=a.school_id and e.campus_id=a.campus_id
        and e.academic_year_id=a.academic_year_id
      join public.students s on s.id=a.student_id and s.school_id=p_school
      join public.classes cl on cl.id=e.class_id
        and cl.campus_id=p_campus and cl.academic_year_id=p_year
      left join public.sections sec on sec.id=e.section_id
        and sec.class_id=e.class_id
      join public.transport_route_stops st on st.id=a.stop_id
        and st.route_id=r.id
      where a.school_id=p_school and a.campus_id=p_campus
        and a.academic_year_id=p_year and a.route_id=r.id
        and a.ends_on is null
    ),'[]'::jsonb)
  ) order by r.route_code),'[]'::jsonb)
  into v_routes from public.transport_routes r
  where r.school_id=p_school and r.campus_id=p_campus;

  return jsonb_build_object(
    'school_id',p_school,
    'campus_id',p_campus,
    'year_id',p_year,
    'year_label',v_year_label,
    'vehicles',v_vehicles,
    'routes',v_routes,
    'vehicles_are_unassigned_to_routes',true,
    'read_only',true
  );
end;
$func$;

-- Data API entrypoints execute with the invoking role but delegate to a
-- private, Owner-authenticated function. No direct table grants are added.
create or replace function public.owner_staff_directory_snapshot(
  p_school uuid,p_campus uuid)
returns jsonb language sql stable security invoker set search_path=''
as $func$
  select app_private.owner_staff_directory_snapshot(p_school,p_campus);
$func$;

create or replace function public.owner_transport_directory_snapshot(
  p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language sql stable security invoker set search_path=''
as $func$
  select app_private.owner_transport_directory_snapshot(p_school,p_campus,p_year);
$func$;

revoke all on function app_private.owner_staff_directory_snapshot(uuid,uuid)
  from public,anon,authenticated;
revoke all on function app_private.owner_transport_directory_snapshot(uuid,uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.owner_staff_directory_snapshot(uuid,uuid)
  from public,anon,authenticated;
revoke all on function public.owner_transport_directory_snapshot(uuid,uuid,uuid)
  from public,anon,authenticated;

grant execute on function app_private.owner_staff_directory_snapshot(uuid,uuid)
  to authenticated;
grant execute on function app_private.owner_transport_directory_snapshot(uuid,uuid,uuid)
  to authenticated;
grant execute on function public.owner_staff_directory_snapshot(uuid,uuid)
  to authenticated;
grant execute on function public.owner_transport_directory_snapshot(uuid,uuid,uuid)
  to authenticated;
