-- Fictional fixture only: Supa Model School / Main Campus / 2026-2027.
-- SAFE TO RE-RUN: only inserts absent SAMPLE-scoped rows; never deletes or
-- rewrites student, finance, auth, payroll or approved attendance evidence.
-- This fixture deliberately does NOT create auth.users or attendance marks.
-- A real authenticated teacher and active policy are required for registers.
-- All names and vehicle numbers are fabricated. Never treat as actual records.
BEGIN;
DO $sample$
DECLARE
  v_school uuid;
  v_campus uuid;
  v_year uuid;
  v_owner uuid;
BEGIN
  SELECT id INTO v_school FROM public.schools
   WHERE name = 'Supa Model School' AND status = 'active';
  IF v_school IS NULL OR (SELECT count(*) FROM public.schools) <> 1 THEN
    RAISE EXCEPTION 'Fixture requires the sole active Supa Model School';
  END IF;
  SELECT id INTO v_campus FROM public.campuses
    WHERE school_id = v_school AND code = 'MAIN' AND is_active;
  SELECT id INTO v_year FROM public.academic_years
    WHERE school_id = v_school AND label = '2026-2027' AND is_active;
  SELECT user_id INTO v_owner FROM public.user_roles
    WHERE school_id = v_school AND role = 'owner' AND is_active LIMIT 1;
  IF v_campus IS NULL OR v_year IS NULL OR v_owner IS NULL OR
    (SELECT count(*) FROM public.students
     WHERE school_id = v_school AND registration_no LIKE 'SAMPLE-2026-%') <> 33 THEN
    RAISE EXCEPTION 'Expected campus/year/Owner and 33 fictional students';
  END IF;

  INSERT INTO public.employee_departments (school_id, code, name)
  SELECT v_school, src.code, src.label FROM (VALUES
    ('SAMPLE_ACADEMICS', 'Academics (Sample)'),
    ('SAMPLE_ADMIN', 'Administration (Sample)'),
    ('SAMPLE_FINANCE', 'Finance (Sample)'),
    ('SAMPLE_TRANSPORT', 'Transport (Sample)'),
    ('SAMPLE_SERVICES', 'Student Services (Sample)')
  ) src(code, label)
  ON CONFLICT (school_id, code) DO NOTHING;

  INSERT INTO public.employee_positions
    (school_id, department_id, code, title, is_teaching_position)
  SELECT v_school, d.id, x.code, x.title, x.teaches
  FROM (VALUES
    ('SAMPLE_PRINCIPAL', 'Principal (Sample)', 'SAMPLE_ADMIN', false),
    ('SAMPLE_TEACHER', 'Class Teacher (Sample)', 'SAMPLE_ACADEMICS', true),
    ('SAMPLE_ACCOUNTANT', 'Accountant (Sample)', 'SAMPLE_FINANCE', false),
    ('SAMPLE_TRANSPORT_MGR', 'Transport Manager (Sample)', 'SAMPLE_TRANSPORT', false),
    ('SAMPLE_DRIVER', 'School Driver (Sample)', 'SAMPLE_TRANSPORT', false),
    ('SAMPLE_LIBRARIAN', 'Librarian (Sample)', 'SAMPLE_SERVICES', false),
    ('SAMPLE_SECURITY', 'Security Officer (Sample)', 'SAMPLE_SERVICES', false),
    ('SAMPLE_NURSE', 'School Nurse (Sample)', 'SAMPLE_SERVICES', false)
  ) x(code, title, dept_code, teaches)
  JOIN public.employee_departments d
   ON d.school_id = v_school AND d.code = x.dept_code
  ON CONFLICT (school_id, code) DO NOTHING;

  INSERT INTO public.employees
    (school_id, employee_no, full_name, full_name_ur,
     hired_on, employment_type, employment_status, created_by)
  SELECT v_school, x.employee_no, x.name, x.urdu,
    x.hired, x.kind, 'active', v_owner
  FROM (VALUES
    ('SAMPLE-EMP-001', 'SAMPLE Farooq Ahmad', 'فاروق احمد', date '2026-04-01', 'permanent'),
    ('SAMPLE-EMP-002', 'SAMPLE Shazia Khan', 'شازیہ خان', date '2026-04-01', 'permanent'),
    ('SAMPLE-EMP-003', 'SAMPLE Rahman Ali', 'رحمان علی', date '2026-04-01', 'permanent'),
    ('SAMPLE-EMP-004', 'SAMPLE Nadia Gul', 'نادیہ گل', date '2026-04-01', 'permanent'),
    ('SAMPLE-EMP-005', 'SAMPLE Iftikhar Ahmad', 'افتخار احمد', date '2026-04-01', 'permanent'),
    ('SAMPLE-EMP-006', 'SAMPLE Hamid Khan', 'حمید خان', date '2026-05-01', 'permanent'),
    ('SAMPLE-EMP-007', 'SAMPLE Nasir Shah', 'ناصر شاہ', date '2026-05-01', 'permanent'),
    ('SAMPLE-EMP-008', 'SAMPLE Aqeel Khan', 'عقیل خان', date '2026-05-01', 'contract'),
    ('SAMPLE-EMP-009', 'SAMPLE Rubina Bibi', 'روبینہ بی بی', date '2026-05-01', 'part_time'),
    ('SAMPLE-EMP-010', 'SAMPLE Usman Afridi', 'عثمان آفریدی', date '2026-05-01', 'contract'),
    ('SAMPLE-EMP-011', 'SAMPLE Samina Bibi', 'ثمینہ بی بی', date '2026-05-01', 'part_time')
  ) x(employee_no, name, urdu, hired, kind)
  ON CONFLICT (school_id, employee_no) DO NOTHING;

  INSERT INTO public.employee_assignments
    (school_id, campus_id, employee_id, department_id, position_id,
     starts_on, primary_assignment, workload_bps, assignment_status,
     approved_by, reason)
  SELECT v_school, v_campus, e.id, d.id, p.id, e.hired_on,
    true, 10000, 'active', v_owner,
    'SAMPLE FIXTURE: fictional employee campus assignment'
  FROM (VALUES
    ('SAMPLE-EMP-001', 'SAMPLE_PRINCIPAL'),
    ('SAMPLE-EMP-002', 'SAMPLE_TEACHER'),
    ('SAMPLE-EMP-003', 'SAMPLE_TEACHER'),
    ('SAMPLE-EMP-004', 'SAMPLE_TEACHER'),
    ('SAMPLE-EMP-005', 'SAMPLE_TEACHER'),
    ('SAMPLE-EMP-006', 'SAMPLE_ACCOUNTANT'),
    ('SAMPLE-EMP-007', 'SAMPLE_TRANSPORT_MGR'),
    ('SAMPLE-EMP-008', 'SAMPLE_DRIVER'),
    ('SAMPLE-EMP-009', 'SAMPLE_LIBRARIAN'),
    ('SAMPLE-EMP-010', 'SAMPLE_SECURITY'),
    ('SAMPLE-EMP-011', 'SAMPLE_NURSE')
  ) x(employee_no, position_code)
  JOIN public.employees e ON e.school_id = v_school
    AND e.employee_no = x.employee_no
  JOIN public.employee_positions p ON p.school_id = v_school
    AND p.code = x.position_code
  JOIN public.employee_departments d ON d.id = p.department_id
  WHERE NOT EXISTS (
    SELECT 1 FROM public.employee_assignments old
    WHERE old.employee_id = e.id AND old.school_id = v_school
      AND old.campus_id = v_campus
      AND old.position_id = p.id AND old.ends_on IS NULL)
  ;

  -- Draft-only school calendar & attendance policy.
  INSERT INTO public.school_calendar_days
    (school_id, campus_id, academic_year_id, calendar_date,
     day_kind, title, reason, created_by)
  SELECT v_school, v_campus, v_year, dt,
    'instructional', 'SAMPLE instructional day',
    'Fictional testing calendar; not an approved actual school day',
    v_owner
  FROM (VALUES (date '2026-11-16'), (date '2026-11-17'),
               (date '2026-11-18')) x(dt)
  ON CONFLICT (campus_id, calendar_date) DO NOTHING;

  INSERT INTO public.attendance_policies
    (school_id, campus_id, academic_year_id,
     version_no, status, first_period_required, after_break_enabled,
     late_after, first_period_submit_deadline,
     allow_backdated_request, effective_from)
  VALUES (v_school, v_campus, v_year, 1, 'draft',
     true, false, time '08:15', time '09:15', false, date '2026-11-16')
  ON CONFLICT (campus_id, academic_year_id, version_no) DO NOTHING;

  INSERT INTO public.transport_vehicles
    (school_id, campus_id, registration_no, capacity, status)
  SELECT v_school, v_campus, x.registration_no, x.capacity, 'active'
  FROM (VALUES
    ('SAMPLE-BUS-001', 24),
    ('SAMPLE-BUS-002', 18)
  ) x(registration_no, capacity)
  ON CONFLICT (school_id, registration_no) DO NOTHING;

  INSERT INTO public.transport_routes
    (school_id, campus_id, route_code, route_name, is_active)
  SELECT v_school, v_campus, x.code, x.title, true
  FROM (VALUES
    ('SAMPLE-RT-01', 'SAMPLE Mingora North Route'),
    ('SAMPLE-RT-02', 'SAMPLE Saidu Sharif Route')
  ) x(code, title)
  ON CONFLICT (campus_id, route_code) DO NOTHING;

  INSERT INTO public.transport_route_stops
    (school_id, campus_id, route_id, stop_order,
     stop_name, pickup_time, dropoff_time)
  SELECT v_school, v_campus, r.id, x.sort, x.title,
    x.pickup, x.dropoff
  FROM (VALUES
    ('SAMPLE-RT-01', 1, 'SAMPLE Mingora Bazaar', time '07:20', time '14:30'),
    ('SAMPLE-RT-01', 2, 'SAMPLE Fizagat Stop', time '07:35', time '14:45'),
    ('SAMPLE-RT-02', 1, 'SAMPLE Saidu Chowk', time '07:15', time '14:30'),
    ('SAMPLE-RT-02', 2, 'SAMPLE College Colony', time '07:30', time '14:45')
  ) x(route_code, sort, title, pickup, dropoff)
  JOIN public.transport_routes r
    ON r.school_id = v_school AND r.campus_id = v_campus
     AND r.route_code = x.route_code
  ON CONFLICT (route_id, stop_order) DO NOTHING;

  -- 12 existing fictional students on two routes, 6 each.
  WITH eligible AS (
    SELECT e.id enrollment_id, e.student_id, e.class_id,
      row_number() OVER (ORDER BY s.registration_no) AS rn
    FROM public.student_enrollments e
    JOIN public.students s ON s.id = e.student_id AND s.school_id = e.school_id
    WHERE e.school_id = v_school AND e.campus_id = v_campus
      AND e.academic_year_id = v_year AND e.ended_on IS NULL
      AND s.registration_no BETWEEN 'SAMPLE-2026-0002' AND 'SAMPLE-2026-0013'
      AND e.admitted_on <= date '2026-11-18'
  )
  INSERT INTO public.transport_student_assignments
    (school_id, campus_id, academic_year_id, class_id,
     student_id, enrollment_id, route_id, stop_id,
     starts_on, approved_by, operation_id)
  SELECT v_school, v_campus, v_year, e.class_id,
    e.student_id, e.enrollment_id, r.id, st.id,
    date '2026-11-18', v_owner, gen_random_uuid()
  FROM eligible e
  JOIN public.transport_routes r ON r.school_id = v_school
   AND r.campus_id = v_campus AND
    r.route_code = CASE WHEN mod(e.rn, 2) = 0
      THEN 'SAMPLE-RT-02' ELSE 'SAMPLE-RT-01' END
  JOIN public.transport_route_stops st ON st.route_id = r.id
   AND st.stop_order = CASE WHEN mod(e.rn, 4) IN (1, 2) THEN 1 ELSE 2 END
  WHERE NOT EXISTS (
    SELECT 1 FROM public.transport_student_assignments x
    WHERE x.school_id = v_school AND x.enrollment_id = e.enrollment_id
    AND x.ends_on IS NULL
  );

  IF (SELECT count(*) FROM public.employees
      WHERE school_id = v_school AND employee_no LIKE 'SAMPLE-EMP-%') <> 11
    OR (SELECT count(*) FROM public.transport_student_assignments t
      JOIN public.transport_routes r ON r.id = t.route_id
      WHERE t.school_id = v_school AND r.route_code LIKE 'SAMPLE-RT-%') <> 12
  THEN RAISE EXCEPTION 'Sample staff/transport fixture counts incomplete';
  END IF;
END $sample$;
COMMIT;

-- Verification: do not imply any payroll, live teacher logins or attendance marks.
SELECT jsonb_build_object(
 'sample_employees', (SELECT count(*) FROM public.employees
   WHERE employee_no LIKE 'SAMPLE-EMP-%'),
 'sample_staff_assignments', (SELECT count(*) FROM public.employee_assignments ea
   JOIN public.employees e ON e.id = ea.employee_id
   WHERE e.employee_no LIKE 'SAMPLE-EMP-%'),
 'sample_departments', (SELECT count(*) FROM public.employee_departments
   WHERE code LIKE 'SAMPLE_%'),
 'sample_positions', (SELECT count(*) FROM public.employee_positions
   WHERE code LIKE 'SAMPLE_%'),
 'calendar_days', (SELECT count(*) FROM public.school_calendar_days
   WHERE title = 'SAMPLE instructional day'),
 'draft_attendance_policies', (SELECT count(*) FROM public.attendance_policies
   WHERE status = 'draft'),
 'attendance_registers', (SELECT count(*) FROM public.attendance_registers),
 'attendance_marks', (SELECT count(*) FROM public.student_attendance_marks),
 'sample_vehicles', (SELECT count(*) FROM public.transport_vehicles
   WHERE registration_no LIKE 'SAMPLE-BUS-%'),
 'sample_routes', (SELECT count(*) FROM public.transport_routes
   WHERE route_code LIKE 'SAMPLE-RT-%'),
 'sample_stops', (SELECT count(*) FROM public.transport_route_stops s
   JOIN public.transport_routes r ON r.id = s.route_id
   WHERE r.route_code LIKE 'SAMPLE-RT-%'),
 'sample_student_transport', (SELECT count(*) FROM public.transport_student_assignments t
   JOIN public.transport_routes r ON r.id = t.route_id
   WHERE r.route_code LIKE 'SAMPLE-RT-%')
) AS verified_seed_counts;