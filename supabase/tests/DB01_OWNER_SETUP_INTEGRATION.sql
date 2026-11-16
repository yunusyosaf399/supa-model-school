-- D02 Owner setup integration checks (transaction-safe; leaves zero writes).
-- Prerequisites: applied DB01 + owner setup RPC, ONE active verified
-- owner, one initial_setup='pending' row and NO academic years.
-- Run in a privileged SQL test session or equivalent local PostgreSQL.
-- DO NOT RUN AFTER INITIAL SETUP HAS ALREADY BEEN COMPLETED.
BEGIN;

DO $guard$
BEGIN
  IF (SELECT count(*) FROM public.user_roles WHERE role='owner' AND is_active) <> 1
     OR (SELECT count(*) FROM public.academic_years) <> 0
     OR (SELECT setting_value->>'status' FROM public.school_settings
        WHERE setting_key='initial_setup') <> 'pending'
  THEN
    RAISE EXCEPTION 'Expected a fresh Owner school pending setup';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.owner_complete_initial_setup(uuid,uuid,text,text,text,text,text,date,date,bigint,bigint)',
    'EXECUTE'
  ) THEN RAISE EXCEPTION 'Anonymous user can execute Owner setup'; END IF;

  IF has_table_privilege('authenticated','public.schools','UPDATE')
     OR has_table_privilege('authenticated','public.campuses','UPDATE')
     OR has_table_privilege('authenticated','public.academic_years','INSERT')
     OR has_table_privilege('authenticated','public.owner_setup_audit_events','INSERT')
  THEN RAISE EXCEPTION 'Unexpected direct authenticated write permission'; END IF;
END $guard$;

SELECT set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;

DO $denied$
BEGIN
  BEGIN
    PERFORM public.owner_complete_initial_setup(
      (SELECT id FROM public.schools LIMIT 1),
      (SELECT id FROM public.campuses LIMIT 1),
      'Test School','Test Campus','PKR','Asia/Karachi',
      '2026-2027',DATE '2026-04-01',DATE '2027-03-31',1,1
    );
    RAISE EXCEPTION 'Unauthorized actor was able to save setup';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $denied$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM public.user_roles
   WHERE role='owner' AND is_active LIMIT 1),true);
SET LOCAL ROLE authenticated;

DO $authorized$
DECLARE
  v_school public.schools%rowtype;
  v_campus public.campuses%rowtype;
  v_response jsonb;
BEGIN
  SELECT * INTO v_school FROM public.schools LIMIT 1;
  SELECT * INTO v_campus FROM public.campuses
    WHERE school_id=v_school.id LIMIT 1;

  BEGIN
    PERFORM public.owner_complete_initial_setup(
      v_school.id,v_campus.id,
      'Test School','Test Campus','XXX','Asia/Karachi',
      '2026-2027',DATE '2026-04-01',DATE '2027-03-31',
      v_school.revision,v_campus.revision);
    RAISE EXCEPTION 'Invalid placeholder currency accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

  BEGIN
    PERFORM public.owner_complete_initial_setup(
      v_school.id,v_campus.id,
      'Test School','Test Campus','PKR','Unknown/Zone',
      '2026-2027',DATE '2026-04-01',DATE '2027-03-31',
      v_school.revision,v_campus.revision);
    RAISE EXCEPTION 'Unknown timezone accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

  BEGIN
    PERFORM public.owner_complete_initial_setup(
      v_school.id,v_campus.id,
      'Test School','Test Campus','PKR','Asia/Karachi',
      '2026-2027',DATE '2026-04-01',DATE '2027-03-31',
      v_school.revision+10,v_campus.revision);
    RAISE EXCEPTION 'Stale update accepted';
  EXCEPTION WHEN serialization_failure THEN NULL; END;

  v_response:=public.owner_complete_initial_setup(
    v_school.id,v_campus.id,'Test School','Test Campus',
    'PKR','Asia/Karachi','2026-2027',
    DATE '2026-04-01',DATE '2027-03-31',
    v_school.revision,v_campus.revision
  );

  IF v_response->>'setup_status' <> 'complete'
     OR (SELECT count(*) FROM public.academic_years WHERE is_active) <> 1
     OR (SELECT count(*) FROM public.owner_setup_audit_events) <> 1
     OR (SELECT setting_value->>'status' FROM public.school_settings
         WHERE setting_key='initial_setup') <> 'complete'
  THEN RAISE EXCEPTION 'Atomic save / audit consistency failed'; END IF;

  BEGIN
    PERFORM public.owner_complete_initial_setup(
      v_school.id,v_campus.id,'Test School','Test Campus',
      'PKR','Asia/Karachi','2026-2027',
      DATE '2026-04-01',DATE '2027-03-31',
      v_school.revision+1,v_campus.revision+1
    );
    RAISE EXCEPTION 'One-time initial setup replay succeeded';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $authorized$;

RESET ROLE;
ROLLBACK;
-- All setup data, test academic year, audit event and school updates rolled back.
