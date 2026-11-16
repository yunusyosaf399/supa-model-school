-- DB02 admission integration against the existing verified first Owner.
-- Scratch fixtures are created under BEGIN and ALWAYS ROLLBACK.
-- This test never creates a real principal account or actual student.
-- It temporarily grants the existing Owner a fictional Principal role inside
-- the rolled-back transaction to test the Principal-only approval branch.
-- No private data is exported or printed.
BEGIN;

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.schools)<>1
     OR (SELECT count(*) FROM public.academic_years)<>0
     OR (SELECT count(*) FROM public.admission_applications)<>0
  THEN RAISE EXCEPTION 'Expected unconfigured single-school test environment'; END IF;
  IF has_table_privilege('authenticated','public.students','SELECT')
     OR has_table_privilege('authenticated','public.admission_applications','INSERT')
     OR has_table_privilege('anon','public.student_documents','SELECT')
  THEN RAISE EXCEPTION 'Unsafe DB02 grants'; END IF;
  IF has_function_privilege('authenticated',
     'app_private.admission_review(uuid,uuid,bigint,uuid,text,text)',
     'EXECUTE') THEN
    RAISE EXCEPTION 'Untrusted principal review call allowed';
  END IF;
END $preflight$;

INSERT INTO public.academic_years(school_id,label,starts_on,ends_on,is_active)
SELECT id,'TMP-DB02-2026-27',DATE '2026-01-01',DATE '2027-12-31',true
FROM public.schools;
INSERT INTO public.classes(school_id,campus_id,academic_year_id,name,sort_order)
SELECT c.school_id,c.id,y.id,'TMP-Grade-One',1
FROM public.campuses c
JOIN public.academic_years y ON y.school_id=c.school_id
WHERE y.label='TMP-DB02-2026-27';
INSERT INTO public.sections(class_id,name)
SELECT id,'A' FROM public.classes WHERE name='TMP-Grade-One';
UPDATE public.school_settings
SET setting_value=jsonb_set(setting_value,'{status}','"complete"'::jsonb)
WHERE setting_key='initial_setup';

DO $test$
DECLARE
  v_owner uuid; v_school uuid; v_campus uuid; v_year uuid;
  v_class uuid; v_section uuid; v_app uuid;
  v_revision bigint; v_response jsonb; v_student uuid;
  v_guardians jsonb :=
    '[{"full_name":"Fictional Guardian","relationship":"father",'
    ||'"phone":"+92-300-1234567","is_primary":true,'
    ||'"is_legal_guardian":true}]';
BEGIN
 SELECT user_id INTO v_owner FROM public.user_roles
 WHERE role='owner' AND is_active LIMIT 1;
 SELECT id INTO v_school FROM public.schools LIMIT 1;
 SELECT id INTO v_campus FROM public.campuses WHERE school_id=v_school LIMIT 1;
 SELECT id INTO v_year FROM public.academic_years WHERE school_id=v_school LIMIT 1;
 SELECT id INTO v_class FROM public.classes WHERE campus_id=v_campus LIMIT 1;
 SELECT id INTO v_section FROM public.sections WHERE class_id=v_class LIMIT 1;

 BEGIN
   PERFORM app_private.admission_save_draft(
     '00000000-0000-4000-8000-000000000001'::uuid,
     v_school,v_campus,v_year,NULL,NULL,
     'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
     'Fictional Child One',DATE '2015-04-02',NULL,
     v_class,v_section,v_guardians);
   RAISE EXCEPTION 'Unknown actor successfully created draft';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 v_app := app_private.admission_save_draft(
     v_owner,v_school,v_campus,v_year,NULL,NULL,
     'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
     'Fictional Child One',DATE '2015-04-02',NULL,
     v_class,v_section,v_guardians);
 IF v_app IS NULL THEN RAISE EXCEPTION 'Draft was not created'; END IF;
 IF (SELECT count(*) FROM public.student_documents WHERE application_id=v_app
    AND document_kind IN ('birth_certificate','transfer_certificate'))<>2
 THEN RAISE EXCEPTION 'Document requirement rows missing'; END IF;
 IF app_private.admission_save_draft(
     v_owner,v_school,v_campus,v_year,NULL,NULL,
     'aaaaaaaa-0000-4000-8000-000000000002'::uuid,
     'Fictional Child One',DATE '2015-04-02',NULL,
     v_class,v_section,v_guardians) IS DISTINCT FROM v_app
 THEN RAISE EXCEPTION 'Draft retry duplicated record'; END IF;

 SELECT revision INTO v_revision
 FROM public.admission_applications WHERE id=v_app;

 BEGIN
   PERFORM app_private.admission_submit(
     v_owner,v_app,v_revision,
     'aaaaaaaa-0000-4000-8000-000000000003'::uuid,
     (CURRENT_DATE + INTERVAL '3 months')::date,'Missing birth certificate');
   RAISE EXCEPTION 'Overlong conditional deadline accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;

 v_response := app_private.admission_submit(
     v_owner,v_app,v_revision,
     'aaaaaaaa-0000-4000-8000-000000000004'::uuid,
     (CURRENT_DATE + INTERVAL '1 month')::date,
     'Missing birth certificate, awaiting the original');

 IF v_response->>'status'<>'submitted'
    OR (v_response->>'approval_required')::boolean IS DISTINCT FROM true
    OR (SELECT count(*) FROM public.students)<>0
    OR (SELECT approval_state FROM public.admission_applications
        WHERE id=v_app)<>'pending'
    OR (SELECT count(*) FROM public.admission_document_deadline_events
        WHERE application_id=v_app)<>1
 THEN RAISE EXCEPTION 'Principal review/conditional deadline state invalid'; END IF;

 -- Even a school-wide Owner cannot approve without a campus Principal role.
 SELECT revision INTO v_revision FROM public.admission_applications WHERE id=v_app;
 BEGIN
   PERFORM app_private.admission_review(
     v_owner,v_app,v_revision,
     'aaaaaaaa-0000-4000-8000-000000000005'::uuid,'approve',NULL);
   RAISE EXCEPTION 'Owner bypassed mandatory Principal review';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;

 -- Simulate explicit campus Principal assignment without adding an Auth user;
 -- this role row and everything below will be rolled back.
 INSERT INTO public.user_roles(user_id,school_id,campus_id,role,is_active)
 VALUES(v_owner,v_school,v_campus,'principal',true);

 v_response := app_private.admission_review(
   v_owner,v_app,v_revision,
   'aaaaaaaa-0000-4000-8000-000000000006'::uuid,'approve',NULL);
 v_student := (v_response->>'student_id')::uuid;

 IF v_response->>'status'<>'approved' OR v_student IS NULL
    OR (SELECT count(*) FROM public.students WHERE school_id=v_school)<>1
    OR (SELECT count(*) FROM public.student_enrollments WHERE school_id=v_school)<>1
    OR (SELECT count(*) FROM public.student_guardians WHERE school_id=v_school)<>1
    OR (SELECT count(*) FROM public.admission_action_events
        WHERE application_id=v_app)<>3
 THEN RAISE EXCEPTION 'Principal finalization not atomic'; END IF;

 -- Repeated operation UUID must not create a second student.
 PERFORM app_private.admission_review(
   v_owner,v_app,v_revision,
   'aaaaaaaa-0000-4000-8000-000000000006'::uuid,'approve',NULL);
 IF (SELECT count(*) FROM public.students WHERE school_id=v_school)<>1
 THEN RAISE EXCEPTION 'Idempotency failure on repeated approval'; END IF;

 IF (SELECT count(*) FROM public.student_documents
     WHERE application_id=v_app AND student_id=v_student)<>2
 THEN RAISE EXCEPTION 'Student document links were not finalized'; END IF;
END $test$;

ROLLBACK;
