-- D04-T03 TRANSACTIONAL PostgreSQL integration test — LOCAL/EPHEMERAL ONLY.
-- Requires applied SQL in the exact order:
-- DB01_foundation, DB02_admissions, DB02_WORKFLOW_SCHEMA,
-- DB02_ADMISSION_OPERATIONS, DB04_OFFLINE_INGEST.
-- Requires the pre-created fictional local Supabase Auth users
-- sms-adm-admin-a@example.invalid and sms-adm-accountant-b@example.invalid.
-- DO NOT run on production; fixture uses an explicitly known TEST credential.
-- psql -X -v ON_ERROR_STOP=1 -f supabase/tests/OFFLINE_INGEST_INTEGRATION.sql
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';

DO $fixture$
DECLARE
  v_admin uuid;
  v_accountant uuid;
  v_school uuid:='11111111-1111-4111-8111-111111111111';
  v_campus uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_other_campus uuid:='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_year uuid:='dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_class uuid:='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
  v_device uuid:='99999999-9999-4999-8999-999999999999';
  v_local uuid:='11111111-aaaa-4111-8111-111111111111';
  v_op1 uuid:='11111111-aaaa-4111-8111-222222222222';
  v_op2 uuid:='22222222-aaaa-4222-8222-222222222222';
  v_op3 uuid:='33333333-aaaa-4333-8333-333333333333';
  v_proof text := pg_catalog.repeat('ab',32);
  v_payload jsonb;
  v_payload2 jsonb;
  v_result jsonb;
  v_second jsonb;
  v_cloud uuid;
  v_revision bigint;
BEGIN
  SELECT id INTO v_admin FROM auth.users
   WHERE email='sms-adm-admin-a@example.invalid';
  SELECT id INTO v_accountant FROM auth.users
   WHERE email='sms-adm-accountant-b@example.invalid';
  IF v_admin IS NULL OR v_accountant IS NULL THEN
    RAISE EXCEPTION 'Create the local fictional Auth accounts first';
  END IF;

  INSERT INTO public.schools(id,name,currency_code,timezone_name)
    VALUES(v_school,'Offline Ingest Fixture School','PKR','Asia/Karachi');
  INSERT INTO public.campuses(id,school_id,code,name)
    VALUES(v_campus,v_school,'A','Campus A'),
          (v_other_campus,v_school,'B','Campus B');
  INSERT INTO public.academic_years(
    id,school_id,label,starts_on,ends_on,is_active)
    VALUES(v_year,v_school,'2026-27','2026-04-01','2027-03-31',true);
  INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
    VALUES(v_class,v_school,v_campus,v_year,'Grade 5');
  INSERT INTO public.user_profiles(user_id,display_name)
    VALUES(v_admin,'Demo Campus A Admin'),
          (v_accountant,'Demo Campus B Accountant');
  INSERT INTO public.user_roles(user_id,school_id,campus_id,role)
    VALUES(v_admin,v_school,v_campus,'admin'),
          (v_accountant,v_school,v_other_campus,'accountant');
  INSERT INTO public.registered_devices(
    id,school_id,assigned_campus_id,registered_user_id,
    display_name,is_offline_enabled)
    VALUES(v_device,v_school,v_campus,v_admin,'Demo Offline Desktop',true);
  INSERT INTO app_private.offline_device_credentials(
    device_id,credential_sha256,expires_at)
    VALUES(v_device,pg_catalog.sha256(pg_catalog.decode(v_proof,'hex')),
           pg_catalog.now()+INTERVAL '2 days');

  v_payload := pg_catalog.jsonb_build_object(
    'operation_id',v_op1::text,
    'local_application_id',v_local::text,
    'academic_year_id',v_year::text,
    'applicant_name','Fictional Offline Child',
    'date_of_birth','2015-02-03',
    'previous_school',null,
    'requested_class_id',v_class::text,
    'requested_section_id',null);
  v_result := app_private.offline_ingest_admission_draft(
    v_admin,v_school,v_campus,v_device,v_proof,
    v_op1,v_local,1,null,v_payload);
  v_cloud := (v_result->>'cloud_application_id')::uuid;
  v_revision := (v_result->>'cloud_revision')::bigint;
  IF v_result->>'status'<>'accepted' OR v_cloud IS NULL OR v_revision<>1
    THEN RAISE EXCEPTION 'First offline draft did not create cloud mapping';
  END IF;
  IF (SELECT count(*) FROM public.admission_applications
      WHERE school_id=v_school)<>1 OR
     (SELECT count(*) FROM app_private.offline_ingest_receipts
      WHERE school_id=v_school)<>1 THEN
    RAISE EXCEPTION 'Duplicate cloud draft or missing receipt';
  END IF;

  -- Lost ACK: exact retry must return the IDENTICAL stored result.
  IF app_private.offline_ingest_admission_draft(
    v_admin,v_school,v_campus,v_device,v_proof,
    v_op1,v_local,1,null,v_payload) <> v_result THEN
    RAISE EXCEPTION 'Idempotent retry did not return same receipt';
  END IF;

  -- Same operation ID with different payload MUST be rejected, not silently
  -- treated as an acceptable retry.
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_campus,v_device,v_proof,
      v_op1,v_local,1,null,
      v_payload||'{"applicant_name":"Tampered Different Name"}'::jsonb);
    RAISE EXCEPTION 'Mutated payload reused accepted operation UUID';
  EXCEPTION WHEN SQLSTATE '23505' THEN NULL;
  END;

  -- Later local revision advances exactly once on the same cloud draft.
  v_payload2 := v_payload || pg_catalog.jsonb_build_object(
    'operation_id',v_op2::text,
    'applicant_name','Fictional Offline Child Revised');
  v_second := app_private.offline_ingest_admission_draft(
    v_admin,v_school,v_campus,v_device,v_proof,
    v_op2,v_local,2,null,v_payload2);
  IF (v_second->>'cloud_application_id')::uuid<>v_cloud OR
     (v_second->>'cloud_revision')::bigint<=v_revision THEN
    RAISE EXCEPTION 'Second local operation failed revision/cloud ID mapping';
  END IF;
  IF (SELECT count(*) FROM public.admission_applications
      WHERE school_id=v_school)<>1 OR
     (SELECT count(*) FROM app_private.offline_ingest_receipts
      WHERE school_id=v_school)<>2 THEN
    RAISE EXCEPTION 'Duplicate cloud record or missing second receipt';
  END IF;

  -- Gap in the local revision sequence must never be accepted.
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_campus,v_device,v_proof,v_op3,v_local,4,null,
      v_payload2||pg_catalog.jsonb_build_object('operation_id',v_op3::text));
    RAISE EXCEPTION 'Out-of-order local revision accepted';
  EXCEPTION WHEN SQLSTATE '40001' THEN NULL;
  END;
  -- Reject cross-campus impersonation, even with the correct device proof.
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_other_campus,v_device,v_proof,
      v_op3,v_local,3,null,
      v_payload2||pg_catalog.jsonb_build_object('operation_id',v_op3::text));
    RAISE EXCEPTION 'Cross-campus device operation accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  -- Wrong user role and wrong device proof each fail.
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_accountant,v_school,v_campus,v_device,v_proof,
      v_op3,v_local,3,null,
      v_payload2||pg_catalog.jsonb_build_object('operation_id',v_op3::text));
    RAISE EXCEPTION 'Unauthorized user accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_campus,v_device,pg_catalog.repeat('cd',32),
      v_op3,v_local,3,null,
      v_payload2||pg_catalog.jsonb_build_object('operation_id',v_op3::text));
    RAISE EXCEPTION 'Incorrect device secret accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  -- Unknown payload fields cannot smuggle additional API instructions.
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_campus,v_device,v_proof,v_op3,v_local,3,null,
      v_payload2||pg_catalog.jsonb_build_object(
        'operation_id',v_op3::text,'unexpected_admin_action',true));
    RAISE EXCEPTION 'Unexpected JSON field accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  -- A live cloud modification after the last accepted offline operation
  -- must cause an optimistic-lock conflict, not last-write-wins.
  UPDATE public.admission_applications
    SET revision=revision+1 WHERE id=v_cloud;
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_campus,v_device,v_proof,v_op3,v_local,3,null,
      v_payload2||pg_catalog.jsonb_build_object('operation_id',v_op3::text));
    RAISE EXCEPTION 'External cloud revision overwritten by stale offline op';
  EXCEPTION WHEN SQLSTATE '40001' THEN NULL;
  END;
  IF (SELECT count(*) FROM app_private.offline_ingest_receipts
      WHERE school_id=v_school)<>2 THEN
    RAISE EXCEPTION 'Failed operation persisted a receipt';
  END IF;
  BEGIN
    UPDATE app_private.offline_ingest_receipts
       SET response_json='{}'::jsonb WHERE school_id=v_school;
    RAISE EXCEPTION 'Receipt was mutable';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  -- Revoked device must not be able to replay even a previously accepted ID.
  UPDATE public.registered_devices SET revoked_at=pg_catalog.now()
    WHERE id=v_device;
  BEGIN
    PERFORM app_private.offline_ingest_admission_draft(
      v_admin,v_school,v_campus,v_device,v_proof,
      v_op1,v_local,1,null,v_payload);
    RAISE EXCEPTION 'Revoked device replay succeeded';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END;
$fixture$;

\echo D04-T03 OFFLINE INGEST INTEGRATION ASSERTIONS PASSED — ROLLBACK
ROLLBACK;
