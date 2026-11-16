-- DB03 Fee/Billing schema acceptance — DISPOSABLE LOCAL POSTGRES ONLY.
-- Precondition: deployed-style DB01/DB02 schema + DB03_FEES_BILLING_SCHEMA.sql,
-- with local fictional auth user sms-adm-admin-a@example.invalid.
-- No payments, account movements or finance posting functions are executed.
-- This script inserts FAKE tests only, and always ROLLS BACK at the end.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB03_FEES_SCHEMA_INTEGRATION.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';

DO $fixture$
DECLARE
  v_actor uuid;
  v_s uuid := '11111111-1111-4111-8111-111111111111';
  v_a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_y uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_class uuid := 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  v_student uuid := '11111111-2222-4333-8444-555555555555';
  v_enroll uuid := '11111111-2222-4333-8444-666666666666';
  v_tuition uuid := '22222222-2222-4222-8222-111111111111';
  v_transport uuid := '22222222-2222-4222-8222-222222222222';
  v_resources uuid := '22222222-2222-4222-8222-333333333333';
  v_plan uuid := '33333333-3333-4333-8333-333333333333';
  v_tuition_item uuid := '33333333-3333-4333-8333-444444444444';
  v_transport_item uuid := '33333333-3333-4333-8333-555555555555';
  v_resource_item uuid := '33333333-3333-4333-8333-666666666666';
  v_cycle uuid := '44444444-4444-4444-8444-444444444444';
  v_charge uuid := '55555555-5555-4555-8555-555555555555';
  v_transport_charge uuid := '55555555-5555-4555-8555-666666666666';
  v_resource_charge uuid := '55555555-5555-4555-8555-777777777777';
  v_r1 uuid := '66666666-6666-4666-8666-111111111111';
  v_r2 uuid := '66666666-6666-4666-8666-222222222222';
  v_credit uuid := '77777777-7777-4777-8777-777777777777';
  v_application uuid := '88888888-8888-4888-8888-888888888888';
  v_found integer;
BEGIN
  SELECT id INTO v_actor FROM auth.users
   WHERE email='sms-adm-admin-a@example.invalid';
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Create fictional local auth user first';
  END IF;
  INSERT INTO public.schools(id,name,currency_code,timezone_name)
   VALUES(v_s,'Fictional Fee Test School','PKR','Asia/Karachi');
  INSERT INTO public.campuses(id,school_id,code,name)
   VALUES(v_a,v_s,'A','Campus A'),(v_b,v_s,'B','Campus B');
  INSERT INTO public.academic_years(
    id,school_id,label,starts_on,ends_on,is_active)
    VALUES(v_y,v_s,'2026-27','2026-04-01','2027-03-31',true);
  INSERT INTO public.classes(
    id,school_id,campus_id,academic_year_id,name)
    VALUES(v_class,v_s,v_a,v_y,'Grade 1');
  INSERT INTO public.students(
    id,school_id,registration_no,full_name_en,date_of_birth)
    VALUES(v_student,v_s,'SMS-TEST-001','Fictional Child','2018-04-13');
  INSERT INTO public.student_enrollments(
    id,student_id,school_id,campus_id,academic_year_id,class_id,admitted_on)
    VALUES(v_enroll,v_student,v_s,v_a,v_y,v_class,'2026-04-01');

  INSERT INTO public.fee_categories(
    id,school_id,code,name,charge_frequency,is_discountable)
    VALUES
    (v_tuition,v_s,'TUITION','Tuition','monthly',true),
    (v_transport,v_s,'TRANSPORT','Transport','monthly',true),
    (v_resources,v_s,'RESOURCES','Books and Resources','one_time',false);
  INSERT INTO public.fee_plans(
    id,school_id,campus_id,academic_year_id,class_id,name,version_no,
    effective_from,status)
    VALUES(v_plan,v_s,v_a,v_y,v_class,'Grade 1 Base Plan',1,
           '2026-04-01','active');
  INSERT INTO public.fee_plan_items(
    id,school_id,campus_id,fee_plan_id,category_id,amount_minor)
    VALUES
    (v_tuition_item,v_s,v_a,v_plan,v_tuition,100000),
    (v_transport_item,v_s,v_a,v_plan,v_transport,30000),
    (v_resource_item,v_s,v_a,v_plan,v_resources,20000);
  INSERT INTO public.fee_billing_cycles(
    id,school_id,campus_id,academic_year_id,billing_month)
    VALUES(v_cycle,v_s,v_a,v_y,'2026-04-01');

  -- 50% tuition scholarship = 5000 basis points; transport/resources
  -- remain separate and not accidentally discounted.
  INSERT INTO public.fee_discounts(
    school_id,campus_id,academic_year_id,student_id,enrollment_id,
    category_id,discount_kind,percent_bps,start_month,
    reason,approved_by)
    VALUES(v_s,v_a,v_y,v_student,v_enroll,v_tuition,
           'percent',5000,'2026-04-01',
           'Approved fictional scholarship',v_actor);
  INSERT INTO public.student_fee_rules(
    school_id,campus_id,academic_year_id,student_id,enrollment_id,
    category_id,rule_kind,amount_minor,start_month,
    reason,approved_by)
    VALUES(v_s,v_a,v_y,v_student,v_enroll,v_transport,
           'override',30000,'2026-04-01',
           'Transport configured by campus',v_actor);
  IF round(100000::numeric*5000/10000,0)<>50000 THEN
    RAISE EXCEPTION 'Integer money percentage rounding changed';
  END IF;

  INSERT INTO public.fee_charges(
    id,school_id,campus_id,academic_year_id,student_id,enrollment_id,
    class_id,billing_cycle_id,billing_month,category_id,fee_plan_id,
    plan_item_id,source_kind,gross_minor,discount_minor,due_on,posted_by)
    VALUES
    (v_charge,v_s,v_a,v_y,v_student,v_enroll,v_class,v_cycle,
     '2026-04-01',v_tuition,v_plan,v_tuition_item,'scheduled',
     100000,50000,'2026-04-10',v_actor),
    (v_transport_charge,v_s,v_a,v_y,v_student,v_enroll,v_class,v_cycle,
     '2026-04-01',v_transport,v_plan,v_transport_item,'scheduled',
     30000,0,'2026-04-10',v_actor),
    (v_resource_charge,v_s,v_a,v_y,v_student,v_enroll,v_class,v_cycle,
     '2026-04-01',v_resources,v_plan,v_resource_item,'scheduled',
     20000,0,'2026-04-10',v_actor);
  IF (SELECT net_minor FROM public.fee_charges WHERE id=v_charge)<>50000
     OR (SELECT net_minor FROM public.fee_charges
          WHERE id=v_transport_charge)<>30000
     OR (SELECT net_minor FROM public.fee_charges
          WHERE id=v_resource_charge)<>20000 THEN
    RAISE EXCEPTION 'Tuition-only scholarship scope or net charge wrong';
  END IF;

  -- Same scheduled charge source key is forbidden even under a NEW UUID.
  BEGIN
    INSERT INTO public.fee_charges(
      school_id,campus_id,academic_year_id,student_id,enrollment_id,
      class_id,billing_cycle_id,billing_month,category_id,fee_plan_id,
      plan_item_id,source_kind,gross_minor,discount_minor,due_on,posted_by)
    VALUES(v_s,v_a,v_y,v_student,v_enroll,v_class,v_cycle,'2026-04-01',
           v_tuition,v_plan,v_tuition_item,'scheduled',100000,0,
           '2026-04-10',v_actor);
    RAISE EXCEPTION 'Duplicate fee charge accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- CROSS CAMPUS mismatch: enrolled in campus A, cannot charge as campus B.
  BEGIN
    INSERT INTO public.fee_charges(
      school_id,campus_id,academic_year_id,student_id,enrollment_id,
      class_id,billing_cycle_id,billing_month,category_id,fee_plan_id,
      plan_item_id,source_kind,gross_minor,discount_minor,due_on,posted_by,
      manual_operation_id)
    VALUES(v_s,v_b,v_y,v_student,v_enroll,v_class,v_cycle,'2026-04-01',
           v_tuition,NULL,NULL,'manual',100000,0,
           '2026-04-10',v_actor,'aaaaaaaa-0000-4000-8000-000000000009');
    RAISE EXCEPTION 'Cross-campus fee source accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;

  -- Two legitimate equal-value partial cash payments are NOT duplicates:
  -- each has a distinct receipt and operation UUID.
  INSERT INTO public.fee_receipts(
    id,school_id,collection_campus_id,student_id,receipt_no,
    operation_id,amount_minor,payment_method,issued_by)
    VALUES
    (v_r1,v_s,v_a,v_student,'SMS-REC-0001',
     'aaaaaaaa-0000-4000-8000-000000000001',20000,'cash',v_actor),
    (v_r2,v_s,v_a,v_student,'SMS-REC-0002',
     'aaaaaaaa-0000-4000-8000-000000000002',20000,'cash',v_actor);
  INSERT INTO public.fee_allocations(
    school_id,student_id,receipt_id,charge_id,amount_minor)
    VALUES(v_s,v_student,v_r1,v_charge,20000),
          (v_s,v_student,v_r2,v_charge,20000);
  IF (SELECT sum(amount_minor) FROM public.fee_allocations
      WHERE charge_id=v_charge)<>40000 THEN
    RAISE EXCEPTION 'Partial receipt allocation changed';
  END IF;
  BEGIN
    INSERT INTO public.fee_receipts(
      school_id,collection_campus_id,student_id,receipt_no,
      operation_id,amount_minor,payment_method,issued_by)
    VALUES(v_s,v_a,v_student,'SMS-REC-0003',
     'aaaaaaaa-0000-4000-8000-000000000001',20000,'cash',v_actor);
    RAISE EXCEPTION 'Duplicate posted payment operation accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  INSERT INTO public.fee_charge_adjustments(
    school_id,student_id,charge_id,operation_id,
    delta_minor,reason,approved_by)
    VALUES(v_s,v_student,v_resource_charge,
           'aaaaaaaa-0000-4000-8000-000000000003',-1000,
           'Approved fictional resource correction',v_actor);
  INSERT INTO public.student_credit_entries(
    id,school_id,student_id,campus_id,entry_kind,
    delta_minor,operation_id,reason,posted_by)
    VALUES(v_credit,v_s,v_student,v_a,'manual_grant',5000,
           'aaaaaaaa-0000-4000-8000-000000000004',
           'Approved fictional student credit',v_actor);
  INSERT INTO public.fee_credit_applications(
    school_id,student_id,credit_entry_id,charge_id,amount_minor,operation_id)
    VALUES(v_s,v_student,v_credit,v_transport_charge,5000,
           'aaaaaaaa-0000-4000-8000-000000000005');
  BEGIN
    INSERT INTO public.fee_credit_applications(
      school_id,student_id,credit_entry_id,charge_id,amount_minor,operation_id)
    VALUES(v_s,v_student,v_credit,v_transport_charge,1000,
           'aaaaaaaa-0000-4000-8000-000000000005');
    RAISE EXCEPTION 'Duplicate credit operation accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  -- Parent bank submission is only PENDING; no receipt is posted by upload.
  INSERT INTO public.fee_payment_submissions(
    school_id,campus_id,student_id,submitted_by,
    claimed_amount_minor,proof_storage_path)
    VALUES(v_s,v_a,v_student,v_actor,12000,'tests/fake-slip-001.png');
  IF (SELECT count(*) FROM public.fee_receipts
      WHERE student_id=v_student)<>2 THEN
    RAISE EXCEPTION 'Pending bank submission was posted to ledger';
  END IF;
  BEGIN
    UPDATE public.fee_payment_submissions SET status='verified'
      WHERE student_id=v_student;
    RAISE EXCEPTION 'Unverified bank slip accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- Admission fee before Principal approval is a deposit tied to the
  -- application rather than inventing an approved student.
  INSERT INTO public.admission_applications(
    id,school_id,campus_id,academic_year_id,applicant_name)
    VALUES(v_application,v_s,v_a,v_y,'Pending Fictional Applicant');
  INSERT INTO public.admission_fee_deposits(
    school_id,campus_id,application_id,amount_minor,payment_method,
    operation_id,received_by)
    VALUES(v_s,v_a,v_application,10000,'cash',
     'aaaaaaaa-0000-4000-8000-000000000006',v_actor);

  -- Debt handoff is ONLY collection responsibility; no duplicate charge.
  INSERT INTO public.fee_collection_assignments(
    school_id,charge_id,from_campus_id,to_campus_id,effective_on,
    reason,operation_id,approved_by)
    VALUES(v_s,v_charge,v_a,v_b,'2026-05-01',
       'Student moved collection campus',
       'aaaaaaaa-0000-4000-8000-000000000007',v_actor);
  IF (SELECT campus_id FROM public.fee_charges WHERE id=v_charge)<>v_a
     OR (SELECT count(*) FROM public.fee_charges
       WHERE student_id=v_student)<>3 THEN
    RAISE EXCEPTION 'Campus debt transfer duplicated original charge';
  END IF;

  INSERT INTO public.fee_operation_receipts(
    school_id,operation_id,action,actor_id,request_sha256,result_json)
    VALUES(v_s,'aaaaaaaa-0000-4000-8000-000000000008',
           'post_receipt',v_actor,decode(repeat('ab',32),'hex'),
           '{"status":"accepted"}'::jsonb);
  BEGIN
    UPDATE public.fee_operation_receipts
      SET result_json='{}'::jsonb WHERE school_id=v_s;
    RAISE EXCEPTION 'Posted fee operation result mutable';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    DELETE FROM public.fee_receipts WHERE id=v_r1;
    RAISE EXCEPTION 'Posted fee receipt could be deleted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    TRUNCATE public.fee_operation_receipts;
    RAISE EXCEPTION 'Posted fee operation receipts can be truncated';
  EXCEPTION WHEN check_violation THEN NULL;
  END;

  -- RLS must be enabled, and anon/authenticated direct table access denied.
  SELECT count(*) INTO v_found
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public'
    AND c.relname IN (
      'fee_categories','fee_plans','fee_plan_items','fee_billing_cycles',
      'student_fee_rules','fee_discounts','fee_charges',
      'fee_charge_adjustments','fee_receipts','fee_allocations',
      'student_credit_entries','fee_credit_applications',
      'fee_receipt_reversals','fee_payment_submissions',
      'fee_collection_assignments','admission_fee_deposits',
      'fee_receipt_counters','fee_operation_receipts')
    AND c.relrowsecurity;
  IF v_found<>18 THEN
    RAISE EXCEPTION 'DB03 RLS incomplete: % of 18 tables',v_found;
  END IF;
  IF pg_catalog.has_table_privilege(
      'authenticated','public.fee_receipts','INSERT')
     OR pg_catalog.has_table_privilege(
      'authenticated','public.fee_receipts','SELECT')
     OR pg_catalog.has_table_privilege(
      'anon','public.fee_charges','SELECT') THEN
    RAISE EXCEPTION 'Unexpected unrestricted client fee access';
  END IF;
END;
$fixture$;

\echo DB03 schema constraints and RLS passed on disposable PostgreSQL — ROLLBACK
ROLLBACK;
