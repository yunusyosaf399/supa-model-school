-- Read-only fixture integrity checks. Safe on Supabase staging/production.
DO $check$
DECLARE
 v_school uuid;
 v_campus uuid;
 v_year uuid;
 v_emp int;
 v_assigned int;
 v_dept int;
 v_pos int;
 v_routes int;
 v_stops int;
 v_vehicles int;
 v_riders int;
 v_calendar int;
 v_pol int;
 v_invalid int;
BEGIN
 SELECT id INTO v_school FROM public.schools WHERE name='Supa Model School' AND status='active';
 SELECT id INTO v_campus FROM public.campuses WHERE school_id=v_school AND code='MAIN';
 SELECT id INTO v_year FROM public.academic_years WHERE school_id=v_school AND label='2026-2027';
 IF v_school IS NULL OR v_campus IS NULL OR v_year IS NULL THEN
   RAISE EXCEPTION 'Expected school fixture not found';
 END IF;
 SELECT count(*) INTO v_emp FROM public.employees WHERE school_id=v_school AND employee_no LIKE 'SAMPLE-EMP-%';
 SELECT count(*) INTO v_assigned FROM public.employee_assignments a JOIN public.employees e ON e.id=a.employee_id
   WHERE a.school_id=v_school AND a.campus_id=v_campus AND e.employee_no LIKE 'SAMPLE-EMP-%';
 SELECT count(*) INTO v_dept FROM public.employee_departments WHERE school_id=v_school AND code LIKE 'SAMPLE_%';
 SELECT count(*) INTO v_pos FROM public.employee_positions WHERE school_id=v_school AND code LIKE 'SAMPLE_%';
 SELECT count(*) INTO v_routes FROM public.transport_routes WHERE school_id=v_school AND campus_id=v_campus AND route_code LIKE 'SAMPLE-RT-%';
 SELECT count(*) INTO v_stops FROM public.transport_route_stops st JOIN public.transport_routes r ON r.id=st.route_id
   WHERE st.school_id=v_school AND st.campus_id=v_campus AND r.route_code LIKE 'SAMPLE-RT-%';
 SELECT count(*) INTO v_vehicles FROM public.transport_vehicles WHERE school_id=v_school AND campus_id=v_campus
   AND registration_no LIKE 'SAMPLE-BUS-%';
 SELECT count(*) INTO v_riders FROM public.transport_student_assignments a JOIN public.transport_routes r ON r.id=a.route_id
   WHERE a.school_id=v_school AND a.campus_id=v_campus AND a.academic_year_id=v_year
     AND r.route_code LIKE 'SAMPLE-RT-%' AND a.ends_on IS NULL;
 SELECT count(*) INTO v_calendar FROM public.school_calendar_days WHERE school_id=v_school AND campus_id=v_campus
   AND title='SAMPLE instructional day';
 SELECT count(*) INTO v_pol FROM public.attendance_policies WHERE school_id=v_school AND campus_id=v_campus
   AND academic_year_id=v_year AND status='draft';
 IF (v_emp,v_assigned,v_dept,v_pos,v_routes,v_stops,v_vehicles,v_riders,v_calendar,v_pol)
   IS DISTINCT FROM (11,11,5,8,2,4,2,12,3,1) THEN
   RAISE EXCEPTION 'Fixture mismatch staff %, assign %, depts %, pos %, routes %, stops %, buses %, riders %, days %, policies %',
     v_emp,v_assigned,v_dept,v_pos,v_routes,v_stops,v_vehicles,v_riders,v_calendar,v_pol;
 END IF;
 SELECT count(*) INTO v_invalid FROM public.transport_student_assignments a
   JOIN public.transport_routes r ON r.id=a.route_id
   JOIN public.transport_route_stops st ON st.id=a.stop_id
   JOIN public.student_enrollments e ON e.id=a.enrollment_id
   JOIN public.students s ON s.id=e.student_id
   WHERE r.route_code LIKE 'SAMPLE-RT-%'
     AND (a.school_id<>e.school_id OR a.campus_id<>e.campus_id OR a.student_id<>e.student_id
          OR a.class_id<>e.class_id OR a.academic_year_id<>e.academic_year_id
          OR st.route_id<>a.route_id OR s.registration_no NOT LIKE 'SAMPLE-2026-%'
          OR a.starts_on<e.admitted_on);
 IF v_invalid<>0 THEN RAISE EXCEPTION 'Invalid sample transport links: %',v_invalid; END IF;
 IF EXISTS (SELECT 1 FROM public.employees WHERE employee_no LIKE 'SAMPLE-EMP-%' AND auth_user_id IS NOT NULL)
 THEN RAISE EXCEPTION 'Sample staff unexpectedly linked to real auth users'; END IF;
 IF EXISTS (SELECT 1 FROM public.attendance_policies WHERE school_id=v_school
  AND campus_id=v_campus AND academic_year_id=v_year AND status='active')
 THEN RAISE EXCEPTION 'Fixture must not activate attendance without real teacher assignments'; END IF;
 IF EXISTS (SELECT 1 FROM public.student_attendance_marks WHERE school_id=v_school)
 THEN RAISE EXCEPTION 'Fixture must not manufacture immutable attendance marks'; END IF;
END $check$;
SELECT 'PASS: 11 staff / 11 assignments / 2 routes / 12 riders / draft attendance policy / no fabricated marks' AS result;