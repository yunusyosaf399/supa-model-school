-- DB10: verified Owner-only, campus-scoped student directory read.
-- No direct authenticated grants on students/enrollments/guardians.
create or replace function app_private.owner_student_directory(
  p_school_id uuid, p_campus_id uuid, p_limit integer default 100, p_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare
  v_actor uuid := (select auth.uid());
  v_year uuid;
  v_total bigint;
  v_rows jsonb;
begin
  if v_actor is null or p_school_id is null or p_campus_id is null
     or p_limit is null or p_limit not between 1 and 200
     or p_offset is null or p_offset < 0 then
    raise exception 'Invalid student directory request' using errcode='22023';
  end if;
  if not exists (
    select 1 from public.user_roles r
    join public.user_profiles pr on pr.user_id = r.user_id
    join auth.users u on u.id = r.user_id
    join public.schools sch on sch.id=r.school_id
    join public.campuses ca on ca.school_id=sch.id
    where r.user_id=v_actor and r.school_id=p_school_id
      and r.role='owner' and r.campus_id is null and r.is_active
      and pr.is_active and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
      and sch.status='active'
      and ca.id=p_campus_id and ca.is_active
  ) then
    raise exception 'Verified Owner access required' using errcode='42501';
  end if;
  select y.id into v_year
    from public.academic_years y
    where y.school_id=p_school_id and y.is_active
    order by y.starts_on desc, y.id limit 1;
  if v_year is null then
    return pg_catalog.jsonb_build_object('total',0,'students','[]'::jsonb);
  end if;

  select count(*) into v_total
  from public.student_enrollments e
  join public.students st on st.id=e.student_id and st.school_id=e.school_id
  where e.school_id=p_school_id and e.campus_id=p_campus_id
    and e.academic_year_id=v_year and e.ended_on is null;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id',q.student_id,'registration_no',q.registration_no,
    'full_name',q.full_name_en,'campus_id',q.campus_id,
    'campus_name',q.campus_name,
    'class_id',q.class_id,'class_name',q.class_name,
    'section_name',q.section_name,'academic_year',q.year_label,
    'status',q.active_status
  ) order by q.full_name_en,q.registration_no),'[]'::jsonb)
  into v_rows
  from (
    select st.id student_id,st.registration_no,st.full_name_en,
      e.campus_id, ca.name campus_name,cl.id class_id,cl.name class_name,
      coalesce(sec.name,'Unassigned') section_name,y.label year_label,
      st.active_status
    from public.student_enrollments e
    join public.students st on st.id=e.student_id and st.school_id=e.school_id
    join public.campuses ca on ca.id=e.campus_id and ca.school_id=e.school_id
    join public.academic_years y on y.id=e.academic_year_id and y.school_id=e.school_id
    join public.classes cl on cl.id=e.class_id
      and cl.school_id=e.school_id and cl.campus_id=e.campus_id
      and cl.academic_year_id=e.academic_year_id
    left join public.sections sec on sec.id=e.section_id and sec.class_id=e.class_id
    where e.school_id=p_school_id and e.campus_id=p_campus_id
      and e.academic_year_id=v_year and e.ended_on is null
    order by st.full_name_en,st.registration_no
    limit p_limit offset p_offset
  ) q;
  return pg_catalog.jsonb_build_object('total',v_total,'students',v_rows);
end
$fn$;

create or replace function public.owner_student_directory(
  p_school_id uuid, p_campus_id uuid, p_limit integer default 100, p_offset integer default 0
) returns jsonb language sql stable security invoker set search_path=''
as $fn$
  select app_private.owner_student_directory(p_school_id,p_campus_id,p_limit,p_offset);
$fn$;
revoke all on function app_private.owner_student_directory(uuid,uuid,integer,integer)
  from public,anon,authenticated;
revoke all on function public.owner_student_directory(uuid,uuid,integer,integer)
  from public,anon,authenticated;
grant execute on function app_private.owner_student_directory(uuid,uuid,integer,integer)
  to authenticated;
grant execute on function public.owner_student_directory(uuid,uuid,integer,integer)
  to authenticated;
