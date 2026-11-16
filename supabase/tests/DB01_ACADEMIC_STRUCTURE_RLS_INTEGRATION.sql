-- DB01 academic-structure Owner integration tests. Local test or a
-- privileged scratch SQL session ONLY; every fabricated record is rolled back.
-- Requires exactly one active Owner, and initial setup still pending.
BEGIN;

DO $guards$ BEGIN
  IF (SELECT count(*) FROM public.academic_years)<>0
     OR (SELECT count(*) FROM public.classes)<>0
     OR (SELECT count(*) FROM public.sections)<>0
     OR (SELECT setting_value->>'status' FROM public.school_settings
         WHERE setting_key='initial_setup') <> 'pending'
  THEN RAISE EXCEPTION 'Academic-structure scratch test needs empty setup'; END IF;

  IF has_function_privilege(
      'anon','public.owner_create_class_with_sections(uuid,uuid,uuid,text,integer,text[])',
      'EXECUTE')
     OR has_table_privilege('authenticated','public.classes','INSERT')
     OR has_table_privilege('authenticated','public.sections','INSERT')
     OR has_table_privilege('authenticated','public.academic_structure_audit_events','INSERT')
  THEN RAISE EXCEPTION 'Unexpected anonymous RPC or client direct DML'; END IF;
END $guards$;

-- Temporary fixture only. Do not create the real academic year here.
INSERT INTO public.academic_years(school_id,label,starts_on,ends_on,is_active)
SELECT id,'SCRATCH-2026-27',DATE '2026-04-01',DATE '2027-03-31',true
FROM public.schools;

-- Even a verified Owner cannot create classes before setup is completed.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM public.user_roles WHERE role='owner' AND is_active LIMIT 1),
  true);
SET LOCAL ROLE authenticated;
DO $pending$ BEGIN
  BEGIN
    PERFORM public.owner_create_class_with_sections(
      (SELECT id FROM public.schools LIMIT 1),
      (SELECT id FROM public.campuses LIMIT 1),
      (SELECT id FROM public.academic_years LIMIT 1),
      'Grade 1',1,ARRAY['A','B']::text[]);
    RAISE EXCEPTION 'Owner was allowed before initial setup';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $pending$;
RESET ROLE;

-- Simulate post-setup state inside the same rollback transaction.
UPDATE public.school_settings
SET setting_value=jsonb_set(setting_value,'{status}','"complete"'::jsonb)
WHERE setting_key='initial_setup';

SELECT set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $deny$ BEGIN
  BEGIN
    PERFORM public.owner_create_class_with_sections(
      (SELECT id FROM public.schools LIMIT 1),
      (SELECT id FROM public.campuses LIMIT 1),
      (SELECT id FROM public.academic_years LIMIT 1),
      'Grade 1',1,ARRAY['A','B']::text[]);
    RAISE EXCEPTION 'Unknown identity created a class';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $deny$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM public.user_roles WHERE role='owner' AND is_active LIMIT 1),
  true);
SET LOCAL ROLE authenticated;
DO $allow$
DECLARE
  sid uuid; cid uuid; yid uuid; result jsonb;
BEGIN
  SELECT id INTO sid FROM public.schools LIMIT 1;
  SELECT id INTO cid FROM public.campuses LIMIT 1;
  SELECT id INTO yid FROM public.academic_years LIMIT 1;

  BEGIN
    PERFORM public.owner_create_class_with_sections(
      sid,cid,yid,'Grade 1',1,ARRAY['A',' a ']::text[]);
    RAISE EXCEPTION 'Duplicate section labels accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

  result := public.owner_create_class_with_sections(
    sid,cid,yid,'Grade 1',1,ARRAY['A','B']::text[]);
  IF result->>'class_name'<>'Grade 1'
     OR jsonb_array_length(result->'sections')<>2
     OR (SELECT count(*) FROM public.classes)<>1
     OR (SELECT count(*) FROM public.sections)<>2
     OR (SELECT count(*) FROM public.academic_structure_audit_events)<>1
  THEN RAISE EXCEPTION 'Academic structure atomic creation failed'; END IF;

  BEGIN
    PERFORM public.owner_create_class_with_sections(
      sid,cid,yid,'grade 1',2,ARRAY['C']::text[]);
    RAISE EXCEPTION 'Case-insensitive duplicate class accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
END $allow$;
RESET ROLE;
ROLLBACK;
