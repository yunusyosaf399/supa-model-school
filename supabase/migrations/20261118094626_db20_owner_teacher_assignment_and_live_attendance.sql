-- DB20: Owner teacher setup + authenticated daily attendance.
-- Private domain data is never exposed by broad SELECT grants. Marks are
-- insert-only evidence with a single confirmed submission per register.
create table if not exists app_private.sms_teacher_section_assignments(
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools(id),
  campus_id uuid not null references public.campuses(id),
  academic_year_id uuid not null references public.academic_years(id),
  class_id uuid not null references public.classes(id),
  section_id uuid not null references public.sections(id),
  teacher_user_id uuid not null references auth.users(id),
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  active boolean not null default true
);
create unique index if not exists sms_teacher_one_active_section
on app_private.sms_teacher_section_assignments(campus_id,academic_year_id,section_id)
where active;
alter table app_private.sms_teacher_section_assignments enable row level security;
revoke all on app_private.sms_teacher_section_assignments from public,anon,authenticated;

create table if not exists app_private.sms_attendance_submission_operations(
  operation_id uuid primary key,
  school_id uuid not null references public.schools(id),
  register_id uuid not null references public.attendance_registers(id),
  actor_id uuid not null references auth.users(id),
  payload_sha256 bytea not null,
  result_json jsonb not null,
  created_at timestamptz not null default now()
);
alter table app_private.sms_attendance_submission_operations enable row level security;
revoke all on app_private.sms_attendance_submission_operations from public,anon,authenticated;

create or replace function app_private.owner_teacher_attendance_setup(
  p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_today date;v_tz text;
begin
 if not app_private.is_verified_school_owner((select auth.uid()),p_school)
    or not exists(select 1 from public.campuses c where c.id=p_campus
      and c.school_id=p_school and c.is_active)
    or not exists(select 1 from public.academic_years y where y.id=p_year
      and y.school_id=p_school)
 then raise exception 'Verified Owner, campus and school year required'
 using errcode='42501';end if;
 select timezone_name into v_tz from public.schools where id=p_school;
 v_today:=(now() at time zone v_tz)::date;
 return jsonb_build_object(
   'school_id',p_school,'campus_id',p_campus,'year_id',p_year,
   'today',v_today,'timezone',v_tz,
   'teachers',coalesce((select jsonb_agg(jsonb_build_object(
     'user_id',r.user_id,'name',up.display_name,'email',u.email,
     'linked_employee',e.employee_no,'linked_employee_id',e.id)
     order by up.display_name)
    from public.user_roles r
    join public.user_profiles up on up.user_id=r.user_id and up.is_active
    join auth.users u on u.id=r.user_id and u.email_confirmed_at is not null
      and u.deleted_at is null and u.is_anonymous is not true
    left join public.employees e on e.school_id=r.school_id
      and e.auth_user_id=r.user_id
    where r.school_id=p_school and r.campus_id=p_campus
      and r.role='teacher' and r.is_active),'[]'::jsonb),
   'employees',coalesce((select jsonb_agg(jsonb_build_object(
     'id',e.id,'number',e.employee_no,'name',e.full_name,
     'linked_user_id',e.auth_user_id) order by e.employee_no)
    from public.employees e
    where e.school_id=p_school and e.employment_status='active'
      and exists(select 1 from public.employee_assignments a
        join public.employee_positions p on p.id=a.position_id
        where a.employee_id=e.id and a.school_id=p_school
        and a.campus_id=p_campus and a.ends_on is null
        and p.is_teaching_position)),'[]'::jsonb),
   'sections',coalesce((select jsonb_agg(jsonb_build_object(
     'class_id',cl.id,'class_name',cl.name,'section_id',sec.id,
     'section_name',sec.name,
     'students',(select count(*) from public.student_enrollments se
       where se.section_id=sec.id and se.academic_year_id=p_year
         and se.ended_on is null),
     'teacher_id',(select a.teacher_user_id
       from app_private.sms_teacher_section_assignments a
       where a.section_id=sec.id and a.academic_year_id=p_year
         and a.campus_id=p_campus and a.active
       limit 1))
     order by cl.sort_order,sec.name)
    from public.classes cl join public.sections sec on sec.class_id=cl.id
    where cl.school_id=p_school and cl.campus_id=p_campus
      and cl.academic_year_id=p_year),'[]'::jsonb),
   'policy',(select jsonb_build_object('id',p.id,'status',p.status,
      'effective_from',p.effective_from,
      'deadline',p.first_period_submit_deadline,
      'after_break_enabled',p.after_break_enabled)
      from public.attendance_policies p where p.school_id=p_school
      and p.campus_id=p_campus and p.academic_year_id=p_year
      order by case when p.status='active' then 0 else 1 end,
         p.version_no desc limit 1),
   'days',coalesce((select jsonb_agg(jsonb_build_object(
     'date',c.calendar_date,'kind',c.day_kind,'title',c.title)
     order by c.calendar_date)
     from public.school_calendar_days c
     where c.school_id=p_school and c.campus_id=p_campus
       and c.academic_year_id=p_year
       and c.calendar_date between v_today-3 and v_today+21),'[]'::jsonb));
end;
$fn$;

create or replace function app_private.owner_assign_section_teacher(
 p_school uuid,p_campus uuid,p_year uuid,p_class uuid,
 p_section uuid,p_teacher uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_existing uuid;v_id uuid;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
   or not exists(select 1 from public.classes c
       join public.sections s on s.class_id=c.id
       where c.id=p_class and s.id=p_section
         and c.school_id=p_school and c.campus_id=p_campus
         and c.academic_year_id=p_year)
   or not exists(select 1 from public.user_roles r
       join public.user_profiles up on up.user_id=r.user_id
       join auth.users u on u.id=r.user_id
       where r.user_id=p_teacher and r.school_id=p_school
         and r.campus_id=p_campus and r.role='teacher' and r.is_active
         and up.is_active and u.email_confirmed_at is not null
         and u.deleted_at is null and u.is_anonymous is not true)
 then raise exception 'Owner, section, or authorized Teacher invalid'
   using errcode='42501';end if;
 perform 1 from public.campuses c where c.id=p_campus
   and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Campus inactive' using errcode='42501';end if;
 select id,teacher_user_id into v_id,v_existing
 from app_private.sms_teacher_section_assignments
 where campus_id=p_campus and academic_year_id=p_year
   and section_id=p_section and active limit 1;
 if v_existing is not distinct from p_teacher and v_id is not null then
   return jsonb_build_object('saved',true,'assignment_id',v_id,
     'teacher_id',p_teacher);
 end if;
 update app_private.sms_teacher_section_assignments set active=false
 where campus_id=p_campus and academic_year_id=p_year
   and section_id=p_section and active;
 insert into app_private.sms_teacher_section_assignments(
   school_id,campus_id,academic_year_id,class_id,section_id,
   teacher_user_id,assigned_by)
 values(p_school,p_campus,p_year,p_class,p_section,p_teacher,v_actor)
 returning id into v_id;
 return jsonb_build_object('saved',true,'assignment_id',v_id,
   'teacher_id',p_teacher);
end;
$fn$;

create or replace function app_private.owner_link_teacher_employee(
 p_school uuid,p_campus uuid,p_teacher uuid,p_employee uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_existing uuid;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
    or not exists(select 1 from public.user_roles r
      where r.user_id=p_teacher and r.school_id=p_school
        and r.campus_id=p_campus and r.role='teacher' and r.is_active)
    or not exists(select 1 from public.employee_assignments a
      join public.employee_positions p on p.id=a.position_id
      where a.employee_id=p_employee and a.school_id=p_school
       and a.campus_id=p_campus and a.ends_on is null
       and a.assignment_status='active' and p.is_teaching_position)
 then raise exception 'Owner, Teacher or teaching employee invalid'
   using errcode='42501';end if;
 select auth_user_id into v_existing from public.employees e
   where e.id=p_employee and e.school_id=p_school
     and e.employment_status='active' for update;
 if not found or (v_existing is not null and v_existing<>p_teacher)
  or exists(select 1 from public.employees e where e.school_id=p_school
       and e.auth_user_id=p_teacher and e.id<>p_employee)
 then raise exception 'Employee already linked or profile unavailable'
 using errcode='23514';end if;
 update public.employees e set auth_user_id=p_teacher,revision=e.revision+1
 where e.id=p_employee and e.school_id=p_school and
   e.auth_user_id is distinct from p_teacher;
 return jsonb_build_object('saved',true,'employee_id',p_employee,
     'teacher_id',p_teacher);
end;
$fn$;

create or replace function app_private.owner_activate_attendance_policy(
 p_school uuid,p_campus uuid,p_year uuid,p_effective date)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_tz text;v_today date;
v_end date;v_policy uuid;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Verified Owner required' using errcode='42501';end if;
 select s.timezone_name,y.ends_on into v_tz,v_end
 from public.schools s join public.academic_years y on y.school_id=s.id
 where s.id=p_school and y.id=p_year and y.is_active;
 if v_tz is null or v_end is null then raise exception 'Active year required'
 using errcode='42501';end if;
 v_today:=(now() at time zone v_tz)::date;
 if p_effective is null or p_effective<v_today or p_effective>v_end then
  raise exception 'Policy must start today or on a future school day'
 using errcode='22023';end if;
 perform 1 from public.campuses c where c.id=p_campus
   and c.school_id=p_school and c.is_active for update;
 if not found then raise exception 'Campus inactive' using errcode='42501';end if;
 if exists(select 1 from public.attendance_policies p
   where p.school_id=p_school and p.campus_id=p_campus
     and p.academic_year_id=p_year and p.status='active')
 then raise exception 'Attendance policy already active'
 using errcode='23514';end if;
 select p.id into v_policy from public.attendance_policies p
 where p.school_id=p_school and p.campus_id=p_campus
   and p.academic_year_id=p_year and p.status='draft'
 order by p.version_no desc limit 1 for update;
 if v_policy is null then raise exception 'Draft policy not configured'
 using errcode='22023';end if;
 update public.attendance_policies p set status='active',
  approved_by=v_actor,effective_from=p_effective
 where p.id=v_policy;
 return jsonb_build_object('saved',true,'policy_id',v_policy,
  'effective_from',p_effective);
end;
$fn$;

create or replace function app_private.owner_create_attendance_day(
 p_school uuid,p_campus uuid,p_year uuid,p_date date,p_kind text)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_actor uuid:=(select auth.uid());v_tz text;v_start date;v_end date;
v_id uuid;v_kind text;
begin
 if not app_private.is_verified_school_owner(v_actor,p_school)
 then raise exception 'Verified Owner required' using errcode='42501';end if;
 select s.timezone_name,y.starts_on,y.ends_on into v_tz,v_start,v_end
 from public.schools s join public.academic_years y on y.school_id=s.id
 where s.id=p_school and y.id=p_year and y.is_active;
 if v_tz is null or p_kind not in ('instructional','exam')
   or p_date is null or p_date<(now() at time zone v_tz)::date
   or p_date<v_start or p_date>v_end
   or not exists(select 1 from public.campuses c where c.id=p_campus
      and c.school_id=p_school and c.is_active)
 then raise exception 'Invalid future instructional/exam school date'
 using errcode='22023';end if;
 insert into public.school_calendar_days(
  school_id,campus_id,academic_year_id,calendar_date,day_kind,
  title,reason,created_by)
 values(p_school,p_campus,p_year,p_date,p_kind,
  'Owner-approved '||replace(p_kind,'_',' ')||' day',
  'Attendance calendar approved by verified school Owner',v_actor)
 on conflict(campus_id,calendar_date) do nothing returning id into v_id;
 if v_id is null then
  select c.id,c.day_kind into v_id,v_kind from public.school_calendar_days c
  where c.campus_id=p_campus and c.calendar_date=p_date
    and c.academic_year_id=p_year and c.school_id=p_school;
  if v_id is null or v_kind<>p_kind then
    raise exception 'Calendar day already configured differently'
 using errcode='23514';end if;
 end if;
 return jsonb_build_object('saved',true,'day_id',v_id,'date',p_date);
end;
$fn$;

create or replace function app_private.teacher_attendance_today()
returns jsonb language plpgsql stable security definer set search_path=''
as $fn$
declare v_context jsonb;v_school uuid;v_campus uuid;v_actor uuid;
v_today date;v_tz text;v_year uuid;v_policy record;v_day uuid;
begin
 v_context:=app_private.staff_session_context();
 if v_context->>'role'<>'teacher'
 then raise exception 'Authorized Teacher role required' using errcode='42501';end if;
 v_school:=(v_context->>'school_id')::uuid;
 v_campus:=(v_context->>'campus_id')::uuid;
 v_actor:=(v_context->>'user_id')::uuid;
 if not app_private.sms_permission_allowed(v_school,v_campus,'attendance.read')
 then raise exception 'Attendance read permission required'
 using errcode='42501';end if;
 select timezone_name into v_tz from public.schools where id=v_school;
 v_today:=(now() at time zone v_tz)::date;
 select y.id into v_year from public.academic_years y
 where y.school_id=v_school and y.is_active
   and v_today between y.starts_on and y.ends_on limit 1;
 select p.* into v_policy from public.attendance_policies p
 where p.school_id=v_school and p.campus_id=v_campus and
   p.academic_year_id=v_year and p.status='active'
   and v_today>=p.effective_from
   and (p.effective_to is null or v_today<=p.effective_to)
 order by p.version_no desc limit 1;
 select c.id into v_day from public.school_calendar_days c
 where c.school_id=v_school and c.campus_id=v_campus
   and c.academic_year_id=v_year and c.calendar_date=v_today
   and c.day_kind in ('instructional','exam');
 return jsonb_build_object(
  'school_id',v_school,'campus_id',v_campus,'year_id',v_year,
  'today',v_today,'timezone',v_tz,
  'policy_active',v_policy.id is not null,
  'school_day',v_day is not null,
  'deadline',v_policy.first_period_submit_deadline,
  'can_submit',v_policy.id is not null and v_day is not null and
    (v_policy.first_period_submit_deadline is null or
     (now() at time zone v_tz)::time <=v_policy.first_period_submit_deadline),
  'sections',coalesce((
    select jsonb_agg(jsonb_build_object(
      'assignment_id',a.id,'class_name',cl.name,'section_name',sec.name,
      'class_id',a.class_id,'section_id',a.section_id,
      'register_id',r.id,'register_status',r.status,
      'students',coalesce((
        select jsonb_agg(jsonb_build_object(
          'enrollment_id',e.id,'student_id',s.id,'name',s.full_name_en,
          'registration',s.registration_no,
          'mark',(select m.mark_status from public.student_attendance_marks m
            where m.register_id=r.id and m.enrollment_id=e.id limit 1))
          order by e.class_roll_no,s.full_name_en)
        from public.student_enrollments e
        join public.students s on s.id=e.student_id and s.school_id=v_school
        where e.school_id=v_school and e.campus_id=v_campus
         and e.academic_year_id=v_year and e.class_id=a.class_id
         and e.section_id=a.section_id and e.admitted_on<=v_today
         and (e.ended_on is null or e.ended_on>=v_today)
         and s.active_status='active'
      ),'[]'::jsonb)
    ) order by cl.sort_order,sec.name)
    from app_private.sms_teacher_section_assignments a
    join public.classes cl on cl.id=a.class_id
    join public.sections sec on sec.id=a.section_id
    left join public.attendance_registers r on r.school_id=v_school
      and r.campus_id=v_campus and r.academic_year_id=v_year
      and r.class_id=a.class_id and r.section_id=a.section_id
      and r.attendance_date=v_today and r.session_kind='first_period'
    where a.school_id=v_school and a.campus_id=v_campus
      and a.academic_year_id=v_year and a.teacher_user_id=v_actor
      and a.active
  ),'[]'::jsonb));
end;
$fn$;

create or replace function app_private.teacher_open_attendance_register(
 p_assignment uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_context jsonb;v_actor uuid;v_school uuid;v_campus uuid;
v_tz text;v_today date;v_assignment record;v_policy record;
v_day uuid;v_duty uuid;v_register uuid;v_taken uuid;v_status text;
begin
 v_context:=app_private.staff_session_context();
 if v_context->>'role'<>'teacher' then
  raise exception 'Teacher login required' using errcode='42501';end if;
 v_actor:=(v_context->>'user_id')::uuid;
 v_school:=(v_context->>'school_id')::uuid;
 v_campus:=(v_context->>'campus_id')::uuid;
 if not app_private.sms_permission_allowed(v_school,v_campus,'attendance.update')
 then raise exception 'Teacher attendance write grant required'
 using errcode='42501';end if;
 select timezone_name into v_tz from public.schools where id=v_school;
 v_today:=(now() at time zone v_tz)::date;
 select a.* into v_assignment
 from app_private.sms_teacher_section_assignments a
 where a.id=p_assignment and a.school_id=v_school
   and a.campus_id=v_campus and a.teacher_user_id=v_actor
   and a.active;
 if not found or not exists(select 1 from public.academic_years y
    where y.id=v_assignment.academic_year_id and y.school_id=v_school
    and y.is_active and v_today between y.starts_on and y.ends_on)
 then raise exception 'No authorized active Teacher section assignment'
 using errcode='42501';end if;
 select p.* into v_policy from public.attendance_policies p
 where p.school_id=v_school and p.campus_id=v_campus
   and p.academic_year_id=v_assignment.academic_year_id
   and p.status='active' and v_today>=p.effective_from
   and (p.effective_to is null or v_today<=p.effective_to)
 limit 1;
 if v_policy.id is null or (v_policy.first_period_submit_deadline is not null
   and (now() at time zone v_tz)::time>v_policy.first_period_submit_deadline)
 then raise exception 'Attendance policy inactive or submission deadline passed'
 using errcode='22023';end if;
 select id into v_day from public.school_calendar_days
 where school_id=v_school and campus_id=v_campus
   and academic_year_id=v_assignment.academic_year_id
   and calendar_date=v_today and day_kind in ('instructional','exam');
 if v_day is null then raise exception 'Today is not an approved school day'
 using errcode='22023';end if;
 perform 1 from public.campuses c
 where c.id=v_campus and c.school_id=v_school and c.is_active for update;
 select d.id,d.assigned_user_id into v_duty,v_taken
 from public.attendance_duties d
 where d.campus_id=v_campus and d.academic_year_id=v_assignment.academic_year_id
   and d.class_id=v_assignment.class_id and d.section_id=v_assignment.section_id
   and d.attendance_date=v_today and d.session_kind='first_period'
   and d.duty_kind='primary';
 if v_duty is null then
  insert into public.attendance_duties(school_id,campus_id,academic_year_id,
   class_id,section_id,attendance_date,session_kind,duty_kind,assigned_user_id)
  values(v_school,v_campus,v_assignment.academic_year_id,
   v_assignment.class_id,v_assignment.section_id,v_today,
   'first_period','primary',v_actor) returning id into v_duty;
 elsif v_taken<>v_actor then
  raise exception 'Today''s attendance duty belongs to another Teacher'
 using errcode='42501';end if;
 select r.id,r.status into v_register,v_status
 from public.attendance_registers r
 where r.campus_id=v_campus and r.academic_year_id=v_assignment.academic_year_id
   and r.class_id=v_assignment.class_id and r.section_id=v_assignment.section_id
   and r.attendance_date=v_today and r.session_kind='first_period';
 if v_register is null then
  insert into public.attendance_registers(school_id,campus_id,academic_year_id,
   class_id,section_id,calendar_day_id,attendance_date,session_kind,
   duty_id,taken_by,source_kind,status)
  values(v_school,v_campus,v_assignment.academic_year_id,
   v_assignment.class_id,v_assignment.section_id,v_day,v_today,
   'first_period',v_duty,v_actor,'online','draft')
  returning id,status into v_register,v_status;
  insert into public.attendance_register_events(
   register_id,school_id,campus_id,operation_id,event_kind,new_status,actor_id)
  values(v_register,v_school,v_campus,gen_random_uuid(),'created','draft',v_actor);
 elsif not exists(select 1 from public.attendance_registers r
     where r.id=v_register and r.taken_by=v_actor and r.duty_id=v_duty)
 then raise exception 'Register owned by another teacher' using errcode='42501';end if;
 return jsonb_build_object('register_id',v_register,'status',v_status);
end;
$fn$;

create or replace function app_private.teacher_submit_attendance(
 p_register uuid,p_marks jsonb,p_operation uuid)
returns jsonb language plpgsql security definer set search_path=''
as $fn$
declare v_context jsonb;v_actor uuid;v_school uuid;v_campus uuid;v_tz text;
v_today date;v_row record;v_register public.attendance_registers%rowtype;
v_policy record;v_expected int;v_item jsonb;v_student uuid;v_enrollment uuid;
v_status text;v_reason text;v_count integer:=0;v_hash bytea;v_previous record;
v_result jsonb;v_existing int;
begin
 v_context:=app_private.staff_session_context();
 if v_context->>'role'<>'teacher' then
  raise exception 'Teacher role required' using errcode='42501';end if;
 v_actor:=(v_context->>'user_id')::uuid;
 v_school:=(v_context->>'school_id')::uuid;
 v_campus:=(v_context->>'campus_id')::uuid;
 if not app_private.sms_permission_allowed(v_school,v_campus,'attendance.update')
 then raise exception 'Attendance permission denied' using errcode='42501';end if;
 if p_register is null or p_operation is null or jsonb_typeof(p_marks)<>'array'
   or jsonb_array_length(p_marks)>250
 then raise exception 'Invalid attendance submission request'
 using errcode='22023';end if;
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(p_marks::text,'UTF8'));
 select op.* into v_previous from app_private.sms_attendance_submission_operations op
 where op.operation_id=p_operation;
 if found then
  if v_previous.register_id<>p_register or
    v_previous.school_id<>v_school or v_previous.actor_id<>v_actor or
    v_previous.payload_sha256<>v_hash
  then raise exception 'Operation reused with changed attendance'
  using errcode='22023';end if;
  return v_previous.result_json;
 end if;
 select * into v_register from public.attendance_registers
   where id=p_register and school_id=v_school and campus_id=v_campus
     and taken_by=v_actor for update;
 if v_register.id is null or v_register.status<>'draft' then
  raise exception 'Only owning Teacher can submit a draft register'
 using errcode='42501';end if;
 select timezone_name into v_tz from public.schools where id=v_school;
 v_today:=(now() at time zone v_tz)::date;
 select p.* into v_policy from public.attendance_policies p
 where p.school_id=v_school and p.campus_id=v_campus
   and p.academic_year_id=v_register.academic_year_id and p.status='active'
   and v_today between p.effective_from
     and coalesce(p.effective_to,v_today)
 limit 1;
 if v_register.attendance_date<>v_today or v_register.session_kind<>'first_period'
   or v_policy.id is null
   or (v_policy.first_period_submit_deadline is not null and
      (now() at time zone v_tz)::time>v_policy.first_period_submit_deadline)
   or not exists(select 1 from app_private.sms_teacher_section_assignments a
     where a.teacher_user_id=v_actor and a.school_id=v_school
       and a.campus_id=v_campus and a.academic_year_id=v_register.academic_year_id
       and a.class_id=v_register.class_id
       and a.section_id=v_register.section_id and a.active)
 then raise exception 'Today''s attendance submission is not authorized or deadline passed'
 using errcode='42501';end if;
 select count(*) into v_expected from public.student_enrollments e
 join public.students s on s.id=e.student_id and s.school_id=e.school_id
 where e.school_id=v_school and e.campus_id=v_campus
   and e.academic_year_id=v_register.academic_year_id
   and e.class_id=v_register.class_id and e.section_id=v_register.section_id
   and e.admitted_on<=v_today and (e.ended_on is null or e.ended_on>=v_today)
   and s.active_status='active';
 if v_expected=0 or jsonb_array_length(p_marks)<>v_expected then
  raise exception 'Every enrolled student must have exactly one attendance mark'
 using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(p_marks) x
   group by x->>'enrollment_id' having count(*)>1) then
   raise exception 'Duplicate student mark' using errcode='22023';end if;
 if exists(select 1 from public.student_attendance_marks m
   where m.register_id=p_register) then
   raise exception 'Draft register already contains immutable marks'
 using errcode='23514';end if;
 for v_item in select value from jsonb_array_elements(p_marks) as e(value) loop
   begin v_enrollment:=(v_item->>'enrollment_id')::uuid;
   exception when invalid_text_representation then
    raise exception 'Invalid enrollment identifier' using errcode='22023';
   end;
   v_status:=v_item->>'status';
   v_reason:=nullif(btrim(coalesce(v_item->>'reason','')),'');
   if v_status not in ('present','absent','late','excused','leave','sick')
     or v_status is null
     or (v_status in ('excused','leave','sick') and
       length(coalesce(v_reason,''))<4)
   then raise exception 'Invalid mark status or missing absence explanation'
 using errcode='22023';end if;
   select e.student_id into v_student from public.student_enrollments e
   join public.students s on s.id=e.student_id and s.active_status='active'
   where e.id=v_enrollment and e.school_id=v_school and e.campus_id=v_campus
     and e.academic_year_id=v_register.academic_year_id
     and e.class_id=v_register.class_id and e.section_id=v_register.section_id
     and e.admitted_on<=v_today and
     (e.ended_on is null or e.ended_on>=v_today);
   if v_student is null then raise exception 'Student outside assigned section'
 using errcode='42501';end if;
   insert into public.student_attendance_marks(
     school_id,campus_id,academic_year_id,class_id,attendance_date,
     session_kind,register_id,enrollment_id,student_id,mark_status,
     reason,marked_by)
   values(v_school,v_campus,v_register.academic_year_id,v_register.class_id,
     v_today,'first_period',p_register,v_enrollment,v_student,v_status,
     v_reason,v_actor);
   v_count:=v_count+1;
 end loop;
 update public.attendance_registers r set status='submitted',
  revision=r.revision+1,submitted_at=now(),updated_at=now()
 where r.id=p_register;
 insert into public.attendance_register_events(register_id,school_id,
   campus_id,operation_id,event_kind,previous_status,new_status,actor_id)
 values(p_register,v_school,v_campus,p_operation,'submitted','draft',
   'submitted',v_actor);
 v_result:=jsonb_build_object('saved',true,'register_id',p_register,
  'status','submitted','marked',v_count);
 insert into app_private.sms_attendance_submission_operations(
   operation_id,school_id,register_id,actor_id,payload_sha256,result_json)
 values(p_operation,v_school,p_register,v_actor,v_hash,v_result);
 return v_result;
end;
$fn$;

create or replace function public.owner_teacher_attendance_setup(
 p_school uuid,p_campus uuid,p_year uuid)
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.owner_teacher_attendance_setup(p_school,p_campus,p_year); $fn$;
create or replace function public.owner_assign_section_teacher(
 p_school uuid,p_campus uuid,p_year uuid,p_class uuid,p_section uuid,p_teacher uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_assign_section_teacher(p_school,p_campus,p_year,p_class,p_section,p_teacher); $fn$;
create or replace function public.owner_link_teacher_employee(
 p_school uuid,p_campus uuid,p_teacher uuid,p_employee uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_link_teacher_employee(p_school,p_campus,p_teacher,p_employee); $fn$;
create or replace function public.owner_activate_attendance_policy(
 p_school uuid,p_campus uuid,p_year uuid,p_effective date)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_activate_attendance_policy(p_school,p_campus,p_year,p_effective); $fn$;
create or replace function public.owner_create_attendance_day(
 p_school uuid,p_campus uuid,p_year uuid,p_date date,p_kind text)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.owner_create_attendance_day(p_school,p_campus,p_year,p_date,p_kind); $fn$;
create or replace function public.teacher_attendance_today()
returns jsonb language sql stable security invoker set search_path=''
as $fn$ select app_private.teacher_attendance_today(); $fn$;
create or replace function public.teacher_open_attendance_register(p_assignment uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.teacher_open_attendance_register(p_assignment); $fn$;
create or replace function public.teacher_submit_attendance(
 p_register uuid,p_marks jsonb,p_operation uuid)
returns jsonb language sql security invoker set search_path=''
as $fn$ select app_private.teacher_submit_attendance(p_register,p_marks,p_operation); $fn$;

revoke all on function
 app_private.owner_teacher_attendance_setup(uuid,uuid,uuid),
 app_private.owner_assign_section_teacher(uuid,uuid,uuid,uuid,uuid,uuid),
 app_private.owner_link_teacher_employee(uuid,uuid,uuid,uuid),
 app_private.owner_activate_attendance_policy(uuid,uuid,uuid,date),
 app_private.owner_create_attendance_day(uuid,uuid,uuid,date,text),
 app_private.teacher_attendance_today(),
 app_private.teacher_open_attendance_register(uuid),
 app_private.teacher_submit_attendance(uuid,jsonb,uuid),
 public.owner_teacher_attendance_setup(uuid,uuid,uuid),
 public.owner_assign_section_teacher(uuid,uuid,uuid,uuid,uuid,uuid),
 public.owner_link_teacher_employee(uuid,uuid,uuid,uuid),
 public.owner_activate_attendance_policy(uuid,uuid,uuid,date),
 public.owner_create_attendance_day(uuid,uuid,uuid,date,text),
 public.teacher_attendance_today(),
 public.teacher_open_attendance_register(uuid),
 public.teacher_submit_attendance(uuid,jsonb,uuid)
from public,anon,authenticated;
grant execute on function
 app_private.owner_teacher_attendance_setup(uuid,uuid,uuid),
 app_private.owner_assign_section_teacher(uuid,uuid,uuid,uuid,uuid,uuid),
 app_private.owner_link_teacher_employee(uuid,uuid,uuid,uuid),
 app_private.owner_activate_attendance_policy(uuid,uuid,uuid,date),
 app_private.owner_create_attendance_day(uuid,uuid,uuid,date,text),
 app_private.teacher_attendance_today(),
 app_private.teacher_open_attendance_register(uuid),
 app_private.teacher_submit_attendance(uuid,jsonb,uuid),
 public.owner_teacher_attendance_setup(uuid,uuid,uuid),
 public.owner_assign_section_teacher(uuid,uuid,uuid,uuid,uuid,uuid),
 public.owner_link_teacher_employee(uuid,uuid,uuid,uuid),
 public.owner_activate_attendance_policy(uuid,uuid,uuid,date),
 public.owner_create_attendance_day(uuid,uuid,uuid,date,text),
 public.teacher_attendance_today(),
 public.teacher_open_attendance_register(uuid),
 public.teacher_submit_attendance(uuid,jsonb,uuid)
to authenticated;
-- These actions become operational in the Owner permissions matrix.
update app_private.sms_permission_catalog
set is_implemented=true
where code in ('attendance.read','attendance.update');
