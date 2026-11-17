-- DB04 attendance acceptance fixture -- disposable LOCAL PostgreSQL ONLY.
-- Requires DB01+DB02 live-style schema and DB03 fee draft (because DB03
-- adds the composite student_enrollments FK scope used by DB04).
-- Requires the fictitious Auth user sms-adm-admin-a@example.invalid.
-- All fixture writes happen inside BEGIN/ROLLBACK. Not for live Supabase.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB04_ATTENDANCE_SCHEMA_INTEGRATION.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';

DO $test$
DECLARE
  v_actor uuid;
  v_school uuid:='11111111-1111-4111-8111-111111111111';
  v_campus_a uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_campus_b uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_year uuid:='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_class uuid:='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  v_section_a uuid:='10000000-0000-4000-8000-000000000001';
  v_section_b uuid:='10000000-0000-4000-8000-000000000002';
  v_student_a uuid:='20000000-0000-4000-8000-000000000001';
  v_student_b uuid:='20000000-0000-4000-8000-000000000002';
  v_enrollment_a uuid:='30000000-0000-4000-8000-000000000001';
  v_enrollment_b uuid:='30000000-0000-4000-8000-000000000002';
  v_day uuid:='40000000-0000-4000-8000-000000000001';
  v_holiday uuid:='40000000-0000-4000-8000-000000000002';
  v_duty uuid:='50000000-0000-4000-8000-000000000001';
  v_after uuid:='50000000-0000-4000-8000-000000000002';
  v_holiday_duty uuid:='50000000-0000-4000-8000-000000000003';
  v_register uuid:='60000000-0000-4000-8000-000000000001';
  v_after_register uuid:='60000000-0000-4000-8000-000000000002';
  v_mark uuid:='70000000-0000-4000-8000-000000000001';
  v_request uuid:='80000000-0000-4000-8000-000000000001';
  v_staff uuid:='90000000-0000-4000-8000-000000000001';
  v_staff_req uuid:='a0000000-0000-4000-8000-000000000001';
  v_count integer;
BEGIN
  SELECT id INTO v_actor FROM auth.users
    WHERE email='sms-adm-admin-a@example.invalid';
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Create fictional LOCAL Auth test user first';
  END IF;
  INSERT INTO public.schools(id,name,currency_code,timezone_name)
    VALUES(v_school,'Fictional Attendance School','PKR','Asia/Karachi');
  INSERT INTO public.campuses(id,school_id,code,name) VALUES
    (v_campus_a,v_school,'CA','Campus A'),
    (v_campus_b,v_school,'CB','Campus B');
  INSERT INTO public.academic_years
    (id,school_id,label,starts_on,ends_on,is_active)
    VALUES(v_year,v_school,'2026-2027','2026-04-01','2027-03-31',true);
  INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
    VALUES(v_class,v_school,v_campus_a,v_year,'Grade 1');
  INSERT INTO public.sections(id,class_id,name)
    VALUES(v_section_a,v_class,'Section A'),(v_section_b,v_class,'Section B');
  INSERT INTO public.user_profiles(user_id,display_name)
    VALUES(v_actor,'Fictional Campus Teacher');
  INSERT INTO public.students
    (id,school_id,registration_no,full_name_en,date_of_birth)
    VALUES(v_student_a,v_school,'AT-001','Fake Student One','2018-02-01'),
          (v_student_b,v_school,'AT-002','Fake Student Two','2018-03-01');
  INSERT INTO public.student_enrollments
    (id,school_id,campus_id,academic_year_id,student_id,
     class_id,section_id,admitted_on)
    VALUES
     (v_enrollment_a,v_school,v_campus_a,v_year,v_student_a,
      v_class,v_section_a,'2026-04-01'),
     (v_enrollment_b,v_school,v_campus_a,v_year,v_student_b,
      v_class,v_section_b,'2026-04-01');

  -- Each school day is campus-scoped, with date in academic year.
  INSERT INTO public.school_calendar_days
    (id,school_id,campus_id,academic_year_id,calendar_date,day_kind,created_by)
    VALUES
    (v_day,v_school,v_campus_a,v_year,'2026-04-06','instructional',v_actor),
    (v_holiday,v_school,v_campus_a,v_year,'2026-04-07','holiday',v_actor);
  BEGIN
    INSERT INTO public.school_calendar_days
      (school_id,campus_id,academic_year_id,calendar_date,day_kind,created_by)
      VALUES(v_school,v_campus_a,v_year,'2028-04-06','instructional',v_actor);
    RAISE EXCEPTION 'Calendar date outside school year accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;

  INSERT INTO public.attendance_policies
    (school_id,campus_id,academic_year_id,status,version_no,
     first_period_required,after_break_enabled,effective_from,approved_by)
    VALUES(v_school,v_campus_a,v_year,'active',1,true,false,
           '2026-04-01',v_actor);
  BEGIN
    INSERT INTO public.attendance_policies
      (school_id,campus_id,academic_year_id,status,version_no,
       effective_from,approved_by)
    VALUES(v_school,v_campus_a,v_year,'active',2,'2026-04-01',v_actor);
    RAISE EXCEPTION 'Duplicate active campus attendance policy accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO public.attendance_duties
    (id,school_id,campus_id,academic_year_id,class_id,section_id,
     attendance_date,session_kind,duty_kind,assigned_user_id)
    VALUES
    (v_duty,v_school,v_campus_a,v_year,v_class,v_section_a,
     '2026-04-06','first_period','primary',v_actor),
    (v_after,v_school,v_campus_a,v_year,v_class,v_section_a,
     '2026-04-06','after_break','primary',v_actor),
    (v_holiday_duty,v_school,v_campus_a,v_year,v_class,v_section_a,
     '2026-04-07','first_period','primary',v_actor);
  BEGIN
    INSERT INTO public.attendance_duties
      (school_id,campus_id,academic_year_id,class_id,section_id,
       attendance_date,session_kind,duty_kind,assigned_user_id)
      VALUES(v_school,v_campus_a,v_year,v_class,v_section_a,
      '2026-04-06','first_period','primary',v_actor);
    RAISE EXCEPTION 'Duplicate first-period teacher duty accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO public.attendance_registers
    (id,school_id,campus_id,academic_year_id,class_id,section_id,
     calendar_day_id,attendance_date,session_kind,duty_id,taken_by)
    VALUES(v_register,v_school,v_campus_a,v_year,v_class,v_section_a,
           v_day,'2026-04-06','first_period',v_duty,v_actor);
  BEGIN
    INSERT INTO public.attendance_registers
      (school_id,campus_id,academic_year_id,class_id,section_id,
       calendar_day_id,attendance_date,session_kind,duty_id,taken_by)
      VALUES(v_school,v_campus_a,v_year,v_class,v_section_a,
             v_day,'2026-04-06','first_period',v_duty,v_actor);
    RAISE EXCEPTION 'Duplicate class register accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  -- Optional after-break is currently DISABLED by campus policy.
  BEGIN
    INSERT INTO public.attendance_registers
      (school_id,campus_id,academic_year_id,class_id,section_id,
       calendar_day_id,attendance_date,session_kind,duty_id,taken_by)
      VALUES(v_school,v_campus_a,v_year,v_class,v_section_a,
             v_day,'2026-04-06','after_break',v_after,v_actor);
    RAISE EXCEPTION 'Disabled after-break attendance accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  BEGIN
    INSERT INTO public.attendance_registers
      (school_id,campus_id,academic_year_id,class_id,section_id,
       calendar_day_id,attendance_date,session_kind,duty_id,taken_by)
      VALUES(v_school,v_campus_a,v_year,v_class,v_section_a,
             v_holiday,'2026-04-07','first_period',v_holiday_duty,v_actor);
    RAISE EXCEPTION 'Holiday student register accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;

  INSERT INTO public.student_attendance_marks
    (id,school_id,campus_id,academic_year_id,class_id,attendance_date,
     session_kind,register_id,enrollment_id,student_id,mark_status,marked_by)
    VALUES(v_mark,v_school,v_campus_a,v_year,v_class,'2026-04-06',
           'first_period',v_register,v_enrollment_a,v_student_a,'absent',v_actor);
  -- A student from Section B cannot be marked in Section A's register.
  BEGIN
    INSERT INTO public.student_attendance_marks
      (school_id,campus_id,academic_year_id,class_id,attendance_date,
       session_kind,register_id,enrollment_id,student_id,mark_status,marked_by)
      VALUES(v_school,v_campus_a,v_year,v_class,'2026-04-06',
        'first_period',v_register,v_enrollment_b,v_student_b,'present',v_actor);
    RAISE EXCEPTION 'CROSS SECTION attendance mark accepted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  -- A campus-B row cannot reference campus-A duty/enrollment/register.
  BEGIN
    INSERT INTO public.student_attendance_marks
      (school_id,campus_id,academic_year_id,class_id,attendance_date,
       session_kind,register_id,enrollment_id,student_id,mark_status,marked_by)
      VALUES(v_school,v_campus_b,v_year,v_class,'2026-04-06',
        'first_period',v_register,v_enrollment_b,v_student_b,'present',v_actor);
    RAISE EXCEPTION 'CROSS CAMPUS mark accepted';
  EXCEPTION WHEN foreign_key_violation OR SQLSTATE '23514' THEN NULL;
  END;
  -- When campus policy enables after-break, a SECOND register is allowed.
  -- Its marks must not double-count pupils in daily first-period totals.
  UPDATE public.attendance_policies SET
    after_break_enabled=true,after_break_submit_deadline='13:00:00'
    WHERE campus_id=v_campus_a AND academic_year_id=v_year;
  INSERT INTO public.attendance_registers
    (id,school_id,campus_id,academic_year_id,class_id,section_id,
     calendar_day_id,attendance_date,session_kind,duty_id,taken_by)
    VALUES(v_after_register,v_school,v_campus_a,v_year,v_class,v_section_a,
           v_day,'2026-04-06','after_break',v_after,v_actor);
  INSERT INTO public.student_attendance_marks
    (school_id,campus_id,academic_year_id,class_id,attendance_date,
     session_kind,register_id,enrollment_id,student_id,mark_status,marked_by)
    VALUES(v_school,v_campus_a,v_year,v_class,'2026-04-06',
           'after_break',v_after_register,v_enrollment_a,v_student_a,
           'present',v_actor);
  IF (SELECT count(*) FROM public.student_attendance_marks
      WHERE student_id=v_student_a AND attendance_date='2026-04-06')<>2
     OR (SELECT count(*) FROM public.student_attendance_marks
      WHERE student_id=v_student_a AND attendance_date='2026-04-06'
        AND session_kind='first_period')<>1 THEN
    RAISE EXCEPTION 'After-break double counted or first period lost';
  END IF;

  BEGIN
    UPDATE public.student_attendance_marks
      SET mark_status='present' WHERE id=v_mark;
    RAISE EXCEPTION 'Original mark overwritten instead of correction';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;

  INSERT INTO public.attendance_register_events
    (register_id,school_id,campus_id,operation_id,event_kind,
     previous_status,new_status,actor_id)
    VALUES(v_register,v_school,v_campus_a,
      'b0000000-0000-4000-8000-000000000001',
      'submitted','draft','submitted',v_actor);
  UPDATE public.attendance_registers
    SET status='submitted',submitted_at=now(),revision=revision+1
    WHERE id=v_register;
  BEGIN
    UPDATE public.attendance_registers
      SET status='draft',submitted_at=NULL,revision=revision+1
      WHERE id=v_register;
    RAISE EXCEPTION 'Submitted register reopened without approval';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;

  -- Requests and decisions are immutable. Proposed approved status must
  -- agree exactly with the request, and each request has at most one decision.
  INSERT INTO public.attendance_correction_requests
    (id,school_id,campus_id,mark_id,proposed_status,
     expected_effective_revision,reason,requested_by,operation_id)
    VALUES(v_request,v_school,v_campus_a,v_mark,'present',1,
      'Correction supported by class register review',v_actor,
      'b0000000-0000-4000-8000-000000000002');
  INSERT INTO public.attendance_correction_decisions
    (school_id,campus_id,request_id,mark_id,decision,approved_status,
     effective_revision_after,decided_by,operation_id)
    VALUES(v_school,v_campus_a,v_request,v_mark,'approved','present',
      2,v_actor,'b0000000-0000-4000-8000-000000000003');
  BEGIN
    INSERT INTO public.attendance_correction_decisions
      (school_id,campus_id,request_id,mark_id,decision,approved_status,
       effective_revision_after,decided_by,operation_id)
      VALUES(v_school,v_campus_a,v_request,v_mark,'approved','absent',
        3,v_actor,'b0000000-0000-4000-8000-000000000004');
    RAISE EXCEPTION 'Approved status different from requested status accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Staff attendance uses Auth profile now; payroll/employee FK comes DB05.
  INSERT INTO public.staff_attendance_records
    (id,school_id,campus_id,academic_year_id,calendar_day_id,
     attendance_date,staff_user_id,status,recorded_by,operation_id)
    VALUES(v_staff,v_school,v_campus_a,v_year,v_day,'2026-04-06',
      v_actor,'present',v_actor,'b0000000-0000-4000-8000-000000000005');
  INSERT INTO public.staff_attendance_correction_requests
    (id,school_id,campus_id,record_id,proposed_status,
     expected_effective_revision,reason,requested_by,operation_id)
    VALUES(v_staff_req,v_school,v_campus_a,v_staff,'leave',1,
      'Approved fictitious staff leave request',v_actor,
      'b0000000-0000-4000-8000-000000000006');
  INSERT INTO public.staff_attendance_correction_decisions
    (school_id,campus_id,request_id,record_id,decision,approved_status,
     effective_revision_after,decided_by,operation_id)
    VALUES(v_school,v_campus_a,v_staff_req,v_staff,'approved','leave',
      2,v_actor,'b0000000-0000-4000-8000-000000000007');
  BEGIN
    DELETE FROM public.staff_attendance_records WHERE id=v_staff;
    RAISE EXCEPTION 'Immutable staff attendance evidence deleted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  BEGIN
    TRUNCATE public.attendance_correction_decisions;
    RAISE EXCEPTION 'Correction evidence TRUNCATE bypass succeeded';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;

  SELECT count(*) INTO v_count
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     AND c.relname IN (
       'school_calendar_days','attendance_policies','attendance_duties',
       'attendance_registers','attendance_register_events',
       'student_attendance_marks','attendance_correction_requests',
       'attendance_correction_decisions','staff_attendance_records',
       'staff_attendance_correction_requests',
       'staff_attendance_correction_decisions'
     ) AND c.relrowsecurity;
  IF v_count<>11 THEN
    RAISE EXCEPTION 'DB04 RLS incomplete (% of 11)',v_count;
  END IF;
  IF pg_catalog.has_table_privilege(
      'authenticated','public.student_attendance_marks','SELECT')
     OR pg_catalog.has_table_privilege(
      'authenticated','public.attendance_registers','INSERT')
     OR pg_catalog.has_table_privilege(
      'anon','public.staff_attendance_records','SELECT') THEN
    RAISE EXCEPTION 'Client unexpectedly granted attendance access';
  END IF;
END;
$test$;

\echo DB04 ATTENDANCE local schema fixture passed — ROLLBACK
ROLLBACK;
