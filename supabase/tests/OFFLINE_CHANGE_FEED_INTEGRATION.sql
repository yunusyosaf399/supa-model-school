-- D04-T04 change-feed integration. LOCAL/DISPOSABLE PostgreSQL ONLY.
-- Requires DB01, DB02, DB02_WORKFLOW_SCHEMA, DB02_ADMISSION_OPERATIONS,
-- DB04_OFFLINE_INGEST and DB04_CHANGE_FEED applied in that order.
-- Create fictional local Auth user sms-adm-admin-a@example.invalid first.
-- Execute psql -X -v ON_ERROR_STOP=1 -f supabase/tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql
-- All fixture writes are rolled back and must not run on hosted production.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL statement_timeout='30s';

DO $test$
DECLARE
  v_actor uuid;
  v_school uuid := '11111111-1111-4111-8111-111111111111';
  v_a uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_b uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_year uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_device uuid := '99999999-9999-4999-8999-999999999999';
  v_proof text := pg_catalog.repeat('ab',32); -- non-secret TEST ONLY
  v_a1 uuid := '11111111-aaaa-4111-8111-111111111111';
  v_a2 uuid := '22222222-aaaa-4222-8222-222222222222';
  v_b1 uuid := '33333333-aaaa-4333-8333-333333333333';
  v_a3 uuid := '44444444-aaaa-4444-8444-444444444444';
  v_rollback uuid := '55555555-aaaa-4555-8555-555555555555';
  v_result jsonb;
  v_first jsonb;
  v_second jsonb;
  v_cursor bigint;
  v_last bigint;
  v_count bigint;
BEGIN
  SELECT id INTO v_actor FROM auth.users
    WHERE email='sms-adm-admin-a@example.invalid';
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Create fictional local admin Auth user first';
  END IF;

  INSERT INTO public.schools(id,name,currency_code,timezone_name)
    VALUES(v_school,'Fictional Cursor Test School','PKR','Asia/Karachi');
  INSERT INTO public.campuses(id,school_id,code,name) VALUES
    (v_a,v_school,'A','Campus A'),
    (v_b,v_school,'B','Campus B');
  INSERT INTO public.academic_years(
    id,school_id,label,starts_on,ends_on,is_active)
    VALUES(v_year,v_school,'2026-27','2026-04-01','2027-03-31',true);
  INSERT INTO public.user_profiles(user_id,display_name)
    VALUES(v_actor,'Fictional Admin A');
  INSERT INTO public.user_roles(user_id,school_id,campus_id,role)
    VALUES(v_actor,v_school,v_a,'admin');
  INSERT INTO public.registered_devices(
    id,school_id,assigned_campus_id,registered_user_id,
    display_name,is_offline_enabled)
    VALUES(v_device,v_school,v_a,v_actor,'Fictional Offline PC',true);
  INSERT INTO app_private.offline_device_credentials(
    device_id,credential_sha256,expires_at)
    VALUES(v_device,pg_catalog.sha256(pg_catalog.decode(v_proof,'hex')),
           pg_catalog.now()+INTERVAL '1 day');

  -- Empty feed: cursor remains '0' and no events are invented.
  v_result := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,0,1);
  IF v_result->'events'<>'[]'::jsonb OR
     v_result->>'next_cursor'<>'0' OR
     (v_result->>'has_more')::boolean
  THEN
    RAISE EXCEPTION 'Empty feed contract mismatch';
  END IF;

  -- A, B, A: campus B must never leak through the campus A feed.
  INSERT INTO public.admission_applications(
    id,school_id,campus_id,academic_year_id,applicant_name)
    VALUES(v_a1,v_school,v_a,v_year,'Fictional A One');
  INSERT INTO public.admission_applications(
    id,school_id,campus_id,academic_year_id,applicant_name)
    VALUES(v_b1,v_school,v_b,v_year,'Fictional B Hidden');
  INSERT INTO public.admission_applications(
    id,school_id,campus_id,academic_year_id,applicant_name)
    VALUES(v_a2,v_school,v_a,v_year,'Fictional A Two');

  v_first := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,0,1);
  IF pg_catalog.jsonb_array_length(v_first->'events')<>1
     OR v_first->'events'->0->'payload'->>'applicant_name'<>'Fictional A One'
     OR (v_first->>'has_more')::boolean IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'First page incorrect'; END IF;
  v_cursor := (v_first->>'next_cursor')::bigint;
  IF v_first->'events'->0->>'change_seq'<>v_cursor::text THEN
    RAISE EXCEPTION 'Lossless decimal cursor format mismatch';
  END IF;

  v_second := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,v_cursor,1);
  IF pg_catalog.jsonb_array_length(v_second->'events')<>1
     OR v_second->'events'->0->'payload'->>'applicant_name'<>'Fictional A Two'
     OR (v_second->>'has_more')::boolean IS DISTINCT FROM false
  THEN RAISE EXCEPTION 'Campus filtering or page 2 failed'; END IF;
  v_last := (v_second->>'next_cursor')::bigint;
  IF v_last <= v_cursor + 1 THEN
    -- Campus B occupies a different global change sequence position.
    RAISE EXCEPTION 'Unexpected sequence gap absence (test isolation)';
  END IF;
  v_result := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,v_last,10);
  IF v_result->'events'<>'[]'::jsonb OR
     (v_result->>'next_cursor')::bigint<>v_last
  THEN RAISE EXCEPTION 'Empty tail changed cursor'; END IF;

  -- Changed row: update must increment cloud revision and produce NEW event.
  UPDATE public.admission_applications
    SET applicant_name='Fictional A One Revised',
        revision=revision+1,updated_at=pg_catalog.now()
    WHERE id=v_a1;
  v_result := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,v_last,10);
  IF pg_catalog.jsonb_array_length(v_result->'events')<>1
     OR v_result->'events'->0->>'event_type'<>'admission.upsert'
     OR v_result->'events'->0->'payload'->>'applicant_name'
          <>'Fictional A One Revised'
     OR v_result->'events'->0->>'revision'<>'2'
  THEN RAISE EXCEPTION 'Updated admission not recorded'; END IF;
  v_last := (v_result->>'next_cursor')::bigint;

  -- Prevent silent admission campus retargeting and unversioned updates.
  BEGIN
    UPDATE public.admission_applications
      SET campus_id=v_b,revision=revision+1 WHERE id=v_a1;
    RAISE EXCEPTION 'Cross-campus scope reassignment succeeded';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  BEGIN
    UPDATE public.admission_applications
      SET applicant_name='Unversioned edit' WHERE id=v_a1;
    RAISE EXCEPTION 'Update without revision increment succeeded';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  IF (SELECT count(*) FROM app_private.offline_admission_change_log
      WHERE school_id=v_school AND campus_id=v_a)<>3 THEN
    RAISE EXCEPTION 'Failed UPDATE added phantom log rows';
  END IF;

  -- Deleted row must surface as a tombstone, without losing cursor position.
  DELETE FROM public.admission_applications WHERE id=v_a2;
  v_result := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,v_last,10);
  IF pg_catalog.jsonb_array_length(v_result->'events')<>1
     OR v_result->'events'->0->>'event_type'<>'admission.delete'
     OR (v_result->'events'->0->'payload'->>'deleted')::boolean
         IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Delete tombstone missing'; END IF;
  v_last := (v_result->>'next_cursor')::bigint;

  -- A nested failed transaction may burn a sequence value; successful
  -- subsequent changes must still be reachable using "seq > cursor".
  BEGIN
    INSERT INTO public.admission_applications(
      id,school_id,campus_id,academic_year_id,applicant_name)
      VALUES(v_rollback,v_school,v_a,v_year,'Rolled Back Example');
    RAISE EXCEPTION 'Simulated rollback' USING ERRCODE='P0001';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN NULL;
  END;
  INSERT INTO public.admission_applications(
    id,school_id,campus_id,academic_year_id,applicant_name)
    VALUES(v_a3,v_school,v_a,v_year,'Committed After Gap');
  v_result := app_private.offline_pull_admission_changes(
    v_actor,v_school,v_a,v_device,v_proof,v_last,10);
  IF pg_catalog.jsonb_array_length(v_result->'events')<>1
     OR v_result->'events'->0->'payload'->>'applicant_name'
         <>'Committed After Gap'
  THEN RAISE EXCEPTION 'Rolled back ID caused cursor to skip event'; END IF;
  v_last := (v_result->>'next_cursor')::bigint;

  -- Reject a future cursor or an invalid page size.
  BEGIN
    PERFORM app_private.offline_pull_admission_changes(
      v_actor,v_school,v_a,v_device,v_proof,9223372036854775807,10);
    RAISE EXCEPTION 'Forged future cursor accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  BEGIN
    PERFORM app_private.offline_pull_admission_changes(
      v_actor,v_school,v_a,v_device,v_proof,0,101);
    RAISE EXCEPTION 'Unbounded query page size accepted';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;

  -- Wrong campus or proof blocks a request, not just its returned rows.
  BEGIN
    PERFORM app_private.offline_pull_admission_changes(
      v_actor,v_school,v_b,v_device,v_proof,0,10);
    RAISE EXCEPTION 'Cross-campus change feed accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  BEGIN
    PERFORM app_private.offline_pull_admission_changes(
      v_actor,v_school,v_a,v_device,pg_catalog.repeat('cd',32),0,10);
    RAISE EXCEPTION 'Invalid device credential accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;

  -- Append-only means a privileged UPDATE/DELETE cannot rewrite history.
  BEGIN
    UPDATE app_private.offline_admission_change_log
       SET payload='{}'::jsonb WHERE school_id=v_school;
    RAISE EXCEPTION 'Change log history was mutable';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;
  BEGIN
    DELETE FROM app_private.offline_admission_change_log
       WHERE school_id=v_school;
    RAISE EXCEPTION 'Change log history could be deleted';
  EXCEPTION WHEN SQLSTATE '23514' THEN NULL;
  END;

  -- All three privilege checks should be false for ordinary clients.
  IF pg_catalog.has_table_privilege(
       'authenticated','app_private.offline_admission_change_log','SELECT')
     OR pg_catalog.has_table_privilege(
       'anon','app_private.offline_admission_change_log','SELECT')
     OR pg_catalog.has_function_privilege(
       'authenticated',
       'app_private.offline_pull_admission_changes(uuid,uuid,uuid,uuid,text,bigint,integer)',
       'EXECUTE')
  THEN RAISE EXCEPTION 'Unsafe direct client access to private change feed';
  END IF;

  UPDATE public.registered_devices
    SET revoked_at=pg_catalog.now() WHERE id=v_device;
  BEGIN
    PERFORM app_private.offline_pull_admission_changes(
      v_actor,v_school,v_a,v_device,v_proof,v_last,1);
    RAISE EXCEPTION 'Revoked desktop continued receiving changes';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END;
$test$;

\echo D04-T04 ADMISSION CHANGE FEED ASSERTIONS PASSED — ROLLBACK
ROLLBACK;
