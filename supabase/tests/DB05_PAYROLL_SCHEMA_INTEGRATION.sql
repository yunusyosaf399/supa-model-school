-- DB05 employees/payroll schema fixture — DISPOSABLE LOCAL PostgreSQL ONLY.
-- Requires DB01, DB02, stacked DB03 and DB04 designs, in order.
-- Provision fictional auth account sms-adm-admin-a@example.invalid first.
-- This writes ONLY fictional data and ROLLS BACK.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB05_PAYROLL_SCHEMA_INTEGRATION.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';
DO $fixture$
DECLARE
  v_actor uuid;
  s uuid := '11111111-1111-4111-8111-111111111111';
  a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  y uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  c uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  sec uuid := 'eeeeeeee-eeee-4eee-8eee-111111111111';
  dep uuid := '11111111-1111-4111-8111-222222222222';
  pos uuid := '11111111-1111-4111-8111-333333333333';
  emp uuid := '22222222-2222-4222-8222-222222222222';
  emp2 uuid := '22222222-2222-4222-8222-333333333333';
  ass_a uuid := '33333333-3333-4333-8333-111111111111';
  ass_b uuid := '33333333-3333-4333-8333-222222222222';
  salary uuid := '44444444-4444-4444-8444-111111111111';
  comp_basic uuid := '44444444-4444-4444-8444-222222222222';
  comp_ded uuid := '44444444-4444-4444-8444-333333333333';
  comp_misc uuid := '44444444-4444-4444-8444-555555555555';
  period_a uuid := '55555555-5555-4555-8555-111111111111';
  period_b uuid := '55555555-5555-4555-8555-222222222222';
  period_may uuid := '55555555-5555-4555-8555-333333333333';
  entry uuid := '66666666-6666-4666-8666-111111111111';
  adv uuid := '77777777-7777-4777-8777-111111111111';
  adv_other uuid := '77777777-7777-4777-8777-222222222222';
  payment1 uuid := '88888888-8888-4888-8888-111111111111';
  payment2 uuid := '88888888-8888-4888-8888-222222222222';
  leave_req uuid := '99999999-9999-4999-8999-111111111111';
  v_count integer;
BEGIN
 SELECT id INTO v_actor FROM auth.users
  WHERE email='sms-adm-admin-a@example.invalid';
 IF v_actor IS NULL THEN
  RAISE EXCEPTION 'Create fictional local Auth user first';
 END IF;

 INSERT INTO public.schools(id,name,currency_code,timezone_name)
  VALUES(s,'Fictional Payroll Test School','PKR','Asia/Karachi');
 INSERT INTO public.campuses(id,school_id,code,name)
  VALUES(a,s,'A','Campus A'),(b,s,'B','Campus B');
 INSERT INTO public.academic_years(
  id,school_id,label,starts_on,ends_on,is_active)
  VALUES(y,s,'2026-2027','2026-04-01','2027-03-31',true);
 INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
  VALUES(c,s,a,y,'Grade 1');
 INSERT INTO public.sections(id,class_id,name)
  VALUES(sec,c,'Section A');
 INSERT INTO public.user_profiles(user_id,display_name)
  VALUES(v_actor,'Fictional Teacher Admin');

 INSERT INTO public.employee_departments(id,school_id,code,name)
  VALUES(dep,s,'ACADEMIC','Academic Department');
 INSERT INTO public.employee_positions(
  id,school_id,department_id,code,title,is_teaching_position)
  VALUES(pos,s,dep,'TEACHER','Primary Teacher',true);
 INSERT INTO public.employees(
  id,school_id,employee_no,full_name,auth_user_id,hired_on,
  employment_type,created_by)
  VALUES(emp,s,'PAY-001','Fictional Employee One',v_actor,
         '2026-01-01','permanent',v_actor);
 -- Employees without a login are valid.
 INSERT INTO public.employees(
  id,school_id,employee_no,full_name,hired_on,
  employment_type,created_by)
  VALUES(emp2,s,'PAY-002','Fictional Employee Two',
         '2026-01-01','part_time',v_actor);

 INSERT INTO public.employee_assignments(
  id,school_id,campus_id,employee_id,department_id,position_id,
  starts_on,primary_assignment,workload_bps,approved_by)
 VALUES
  (ass_a,s,a,emp,dep,pos,'2026-01-01',true,6000,v_actor),
  (ass_b,s,b,emp,dep,pos,'2026-01-01',false,4000,v_actor);
 IF (SELECT count(*) FROM public.employee_assignments
      WHERE employee_id=emp)<>2 THEN
  RAISE EXCEPTION 'Multi-campus employee assignments not retained';
 END IF;
 INSERT INTO public.employee_teaching_assignments(
  school_id,campus_id,academic_year_id,class_id,section_id,
  employee_assignment_id,employee_id,teacher_user_id,subject_label,
  starts_on,approved_by)
 VALUES(s,a,y,c,sec,ass_a,emp,v_actor,'Mathematics','2026-04-01',v_actor);

 INSERT INTO public.payroll_components(
  id,school_id,code,name,component_kind)
 VALUES
  (comp_basic,s,'BASIC','Basic Salary','earning'),
  (comp_ded,s,'DEDUCTION','Regular Deduction','deduction'),
  (comp_misc,s,'OTHER_EARN','Other Earning','earning');
 INSERT INTO public.salary_structures(
  id,school_id,campus_id,employee_id,employee_assignment_id,version_no,
  pay_basis,effective_from,status,approved_by)
 VALUES(salary,s,a,emp,ass_a,1,'monthly','2026-04-01','active',v_actor);
 INSERT INTO public.salary_structure_lines(
  school_id,salary_structure_id,component_id,component_kind,rate_minor)
 VALUES(s,salary,comp_basic,'earning',100000),
       (s,salary,comp_ded,'deduction',10000);
 BEGIN
  INSERT INTO public.salary_structure_lines(
   school_id,salary_structure_id,component_id,component_kind,rate_minor)
  VALUES(s,salary,comp_misc,'deduction',10000);
  RAISE EXCEPTION 'Salary component kind mismatch accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;

 -- Fictional leave request; approved leave day must not appear twice
 -- even if the employee works at two campuses.
 INSERT INTO public.employee_leave_requests(
  id,school_id,campus_id,employee_id,employee_assignment_id,leave_kind,
  starts_on,ends_on,reason,request_operation_id,requested_by)
 VALUES(leave_req,s,a,emp,ass_a,'annual','2026-04-20','2026-04-21',
 'Fictional annual leave plan','aaaaaaaa-0000-4000-8000-000000000001',v_actor);
 UPDATE public.employee_leave_requests SET status='approved',
   reviewed_by=v_actor,reviewed_at=now() WHERE id=leave_req;
 INSERT INTO public.employee_leave_days(
  school_id,campus_id,employee_id,leave_request_id,leave_date,paid_day,
  recorded_by,operation_id)
 VALUES(s,a,emp,leave_req,'2026-04-20',true,v_actor,
   'aaaaaaaa-0000-4000-8000-000000000002');
 BEGIN
  INSERT INTO public.employee_leave_days(
   school_id,campus_id,employee_id,leave_request_id,leave_date,paid_day,
   recorded_by,operation_id)
  VALUES(s,a,emp,leave_req,'2026-04-20',true,v_actor,
    'aaaaaaaa-0000-4000-8000-000000000003');
  RAISE EXCEPTION 'Duplicate leave day accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;

 INSERT INTO public.payroll_periods(
  id,school_id,campus_id,payroll_month,period_start,period_end)
 VALUES
  (period_a,s,a,'2026-04-01','2026-04-01','2026-04-30'),
  (period_b,s,b,'2026-04-01','2026-04-01','2026-04-30'),
  (period_may,s,b,'2026-05-01','2026-05-01','2026-05-31');

 -- Salary gross 1,000; deductions 100; advance recovery 150;
 -- take-home salary = 750. All values use minor units.
 INSERT INTO public.payroll_entries(
  id,school_id,campus_id,employee_id,employee_assignment_id,
  salary_structure_id,payroll_period_id,payroll_month,gross_minor,
  regular_deductions_minor,advance_recovery_minor,operation_id,assessed_by)
 VALUES(entry,s,a,emp,ass_a,salary,period_a,'2026-04-01',
 100000,10000,15000,
 'aaaaaaaa-0000-4000-8000-000000000004',v_actor);
 IF (SELECT net_minor FROM public.payroll_entries WHERE id=entry)<>75000 THEN
  RAISE EXCEPTION 'Advance recovery changed salary expense calculation';
 END IF;
 -- Two campus payroll periods cannot double-pay the same employee/month.
 BEGIN
  INSERT INTO public.payroll_entries(
   school_id,campus_id,employee_id,employee_assignment_id,
   salary_structure_id,payroll_period_id,payroll_month,gross_minor,
   regular_deductions_minor,advance_recovery_minor,operation_id,assessed_by)
  VALUES(s,a,emp,ass_a,salary,period_a,'2026-04-01',100000,0,0,
   'aaaaaaaa-0000-4000-8000-000000000005',v_actor);
  RAISE EXCEPTION 'Duplicate employee monthly salary accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 -- Fake campus B payroll using the campus A assignment must fail scoped FK.
 BEGIN
  INSERT INTO public.payroll_entries(
   school_id,campus_id,employee_id,employee_assignment_id,
   salary_structure_id,payroll_period_id,payroll_month,gross_minor,
   regular_deductions_minor,advance_recovery_minor,operation_id,assessed_by)
  VALUES(s,b,emp,ass_a,salary,period_may,'2026-05-01',50000,0,0,
   'aaaaaaaa-0000-4000-8000-000000000006',v_actor);
  RAISE EXCEPTION 'Cross-campus payroll assignment accepted';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;

 INSERT INTO public.payroll_entry_lines(
  school_id,campus_id,employee_id,payroll_entry_id,
  component_id,component_kind,amount_minor)
 VALUES(s,a,emp,entry,comp_basic,'earning',100000),
       (s,a,emp,entry,comp_ded,'deduction',10000);
 INSERT INTO public.payroll_cost_allocations(
  school_id,employee_id,payroll_entry_id,cost_campus_id,allocated_gross_minor)
 VALUES(s,emp,entry,a,60000),(s,emp,entry,b,40000);
 IF (SELECT sum(allocated_gross_minor)
  FROM public.payroll_cost_allocations
  WHERE payroll_entry_id=entry)<>100000 THEN
  RAISE EXCEPTION 'Multi-campus payroll cost split incorrect';
 END IF;

 INSERT INTO public.salary_advances(
  id,school_id,employee_id,issuing_campus_id,amount_minor,advanced_on,
  operation_id,approved_by,issued_by,reason)
 VALUES(adv,s,emp,a,40000,'2026-03-25',
  'aaaaaaaa-0000-4000-8000-000000000007',v_actor,v_actor,
  'Fictional salary advance');
 INSERT INTO public.salary_advances(
  id,school_id,employee_id,issuing_campus_id,amount_minor,advanced_on,
  operation_id,approved_by,issued_by,reason)
 VALUES(adv_other,s,emp2,b,20000,'2026-03-25',
  'aaaaaaaa-0000-4000-8000-000000000008',v_actor,v_actor,
  'Another fictional employee advance');
 INSERT INTO public.advance_repayments(
  school_id,campus_id,employee_id,payroll_entry_id,advance_id,
  recovered_minor,operation_id)
 VALUES(s,a,emp,entry,adv,15000,'aaaaaaaa-0000-4000-8000-000000000009');
 BEGIN
  INSERT INTO public.advance_repayments(
   school_id,campus_id,employee_id,payroll_entry_id,advance_id,
   recovered_minor,operation_id)
  VALUES(s,a,emp,entry,adv,15000,
   'aaaaaaaa-0000-4000-8000-00000000000a');
  RAISE EXCEPTION 'Double recovery of same advance/payroll accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 BEGIN
  INSERT INTO public.advance_repayments(
   school_id,campus_id,employee_id,payroll_entry_id,advance_id,
   recovered_minor,operation_id)
  VALUES(s,a,emp,entry,adv_other,15000,
   'aaaaaaaa-0000-4000-8000-00000000000b');
  RAISE EXCEPTION 'Other employee advance recovered from this salary';
 EXCEPTION WHEN foreign_key_violation THEN NULL;
 END;

 -- Two different partial salary payments are valid; same operation UUID
 -- must NOT duplicate. Account movements are reserved for DB06.
 INSERT INTO public.salary_payments(
  id,school_id,campus_id,employee_id,payroll_entry_id,amount_minor,
  method,operation_id,paid_by)
 VALUES
  (payment1,s,a,emp,entry,30000,'cash',
   'aaaaaaaa-0000-4000-8000-00000000000c',v_actor),
  (payment2,s,a,emp,entry,45000,'cash',
   'aaaaaaaa-0000-4000-8000-00000000000d',v_actor);
 IF (SELECT sum(amount_minor) FROM public.salary_payments
     WHERE payroll_entry_id=entry)<>75000 THEN
  RAISE EXCEPTION 'Two partial salary payments not retained';
 END IF;
 BEGIN
  INSERT INTO public.salary_payments(
   school_id,campus_id,employee_id,payroll_entry_id,amount_minor,
   method,operation_id,paid_by)
  VALUES(s,a,emp,entry,30000,'cash',
   'aaaaaaaa-0000-4000-8000-00000000000c',v_actor);
  RAISE EXCEPTION 'Duplicate salary payment operation accepted';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 INSERT INTO public.salary_payment_reversals(
  school_id,employee_id,payment_id,reversal_operation_id,
  reason,approved_by)
 VALUES(s,emp,payment1,'aaaaaaaa-0000-4000-8000-00000000000e',
 'Fictional audited payment reversal',v_actor);
 BEGIN
  INSERT INTO public.salary_payment_reversals(
   school_id,employee_id,payment_id,reversal_operation_id,reason,approved_by)
  VALUES(s,emp,payment1,'aaaaaaaa-0000-4000-8000-00000000000f',
  'Unapproved duplicate reversal attempt',v_actor);
  RAISE EXCEPTION 'Payment reversed twice';
 EXCEPTION WHEN unique_violation THEN NULL;
 END;
 INSERT INTO public.payroll_adjustments(
  school_id,employee_id,payroll_entry_id,operation_id,
  delta_net_minor,adjustment_kind,reason,approved_by)
 VALUES(s,emp,entry,'aaaaaaaa-0000-4000-8000-000000000010',
        1000,'correction','Fictional payroll correction',v_actor);

 INSERT INTO public.payroll_operation_receipts(
  school_id,operation_id,action,actor_id,request_sha256,result_json)
 VALUES(s,'aaaaaaaa-0000-4000-8000-000000000011',
   'post_payroll',v_actor,decode(repeat('ab',32),'hex'),
   '{"status":"accepted"}'::jsonb);
 BEGIN
  UPDATE public.payroll_entries SET gross_minor=200000 WHERE id=entry;
  RAISE EXCEPTION 'Immutable salary assessment modified';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 BEGIN
  DELETE FROM public.salary_payments WHERE id=payment2;
  RAISE EXCEPTION 'Immutable partial salary payment deleted';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;
 BEGIN
  TRUNCATE public.payroll_operation_receipts;
  RAISE EXCEPTION 'Posted payroll receipt was truncated';
 EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
 END;

 SELECT count(*) INTO v_count FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public'
    AND c.relname IN (
     'employee_departments','employee_positions','employees',
     'employee_assignments','employee_teaching_assignments',
     'payroll_components','salary_structures','salary_structure_lines',
     'employee_leave_requests','employee_leave_days','payroll_periods',
     'payroll_entries','payroll_entry_lines','payroll_cost_allocations',
     'payroll_adjustments','salary_advances','advance_repayments',
     'salary_payments','salary_payment_reversals',
     'payroll_operation_receipts') AND c.relrowsecurity;
 IF v_count<>20 THEN
  RAISE EXCEPTION 'DB05 RLS missing on % of 20 tables',20-v_count;
 END IF;
 IF pg_catalog.has_table_privilege(
     'authenticated','public.salary_payments','SELECT')
    OR pg_catalog.has_table_privilege(
     'authenticated','public.employees','INSERT')
    OR pg_catalog.has_table_privilege(
     'anon','public.payroll_entries','SELECT') THEN
  RAISE EXCEPTION 'Client directly granted employee payroll table access';
 END IF;
END;
$fixture$;
\echo DB05 LOCAL PAYROLL CONSTRAINT/RLS TESTS PASSED — ROLLBACK
ROLLBACK;
