-- Admission Academic Lookup / DB01 RLS regression (read-only client).
-- Uses transactional fixtures and ROLLBACK. Does NOT deploy DB02 or admit
-- students. Requires the one active school and Owner from DB01.
BEGIN;

DO $preflight$
BEGIN
  IF (SELECT count(*) FROM public.schools) <> 1
    OR (SELECT count(*) FROM public.academic_years) <> 0
    OR (SELECT count(*) FROM public.classes) <> 0
    OR (SELECT count(*) FROM public.sections) <> 0
  THEN RAISE EXCEPTION 'Only run with empty academic fixture tables'; END IF;
  IF has_table_privilege('anon','public.classes','SELECT')
     OR has_table_privilege('anon','public.sections','SELECT')
     OR has_table_privilege('anon','public.academic_years','SELECT')
  THEN RAISE EXCEPTION 'Anonymous academic table read grant detected'; END IF;
  IF has_table_privilege('authenticated','public.classes','INSERT')
     OR has_table_privilege('authenticated','public.sections','INSERT')
  THEN RAISE EXCEPTION 'Direct academic creation incorrectly granted'; END IF;
END $preflight$;

-- One in-scope year, class and section. Only privileged setup fixture can
-- insert; the admissions client uses SELECT-only under authenticated RLS.
INSERT INTO public.academic_years(school_id,label,starts_on,ends_on,is_active)
SELECT id,'TMP-FIRST-SCHOOL-YEAR',DATE '2026-04-01',DATE '2027-03-31',true
  FROM public.schools;

INSERT INTO public.classes(school_id,campus_id,academic_year_id,name,sort_order)
SELECT s.id,c.id,y.id,'TMP-Grade-One',1
FROM public.schools s
JOIN public.campuses c ON c.school_id=s.id
JOIN public.academic_years y ON y.school_id=s.id
WHERE y.label='TMP-FIRST-SCHOOL-YEAR';

INSERT INTO public.sections(class_id,name)
SELECT id,'TMP-Section-A' FROM public.classes
WHERE name='TMP-Grade-One';

-- Another school's year and academic masters: must remain invisible.
INSERT INTO public.schools(id,name,currency_code,timezone_name)
VALUES ('22222222-2222-4222-8222-222222222222','TMP-Foreign-School','PKR','Asia/Karachi');
INSERT INTO public.campuses(id,school_id,code,name)
VALUES ('33333333-3333-4333-8333-333333333333',
  '22222222-2222-4222-8222-222222222222','TEST','TMP-Foreign-Campus');
INSERT INTO public.academic_years(id,school_id,label,starts_on,ends_on,is_active)
VALUES ('44444444-4444-4444-8444-444444444444',
 '22222222-2222-4222-8222-222222222222','TMP-FOREIGN-YEAR',
 DATE '2026-04-01',DATE '2027-03-31',true);
INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
VALUES ('55555555-5555-4555-8555-555555555555',
 '22222222-2222-4222-8222-222222222222',
 '33333333-3333-4333-8333-333333333333',
 '44444444-4444-4444-8444-444444444444','TMP-Other-Grade');
INSERT INTO public.sections(class_id,name)
VALUES ('55555555-5555-4555-8555-555555555555','TMP-Other-Section');

-- The verified in-school Owner sees only their school's fixtures.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM public.user_roles
    WHERE role='owner' AND is_active LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $check_owner$
BEGIN
  IF (SELECT count(*) FROM public.campuses) <> 1
     OR (SELECT count(*) FROM public.academic_years) <> 1
     OR (SELECT count(*) FROM public.classes) <> 1
     OR (SELECT count(*) FROM public.sections) <> 1
  THEN RAISE EXCEPTION 'Owner campus/year/class/section isolation failed'; END IF;
  IF EXISTS (SELECT 1 FROM public.classes WHERE name='TMP-Other-Grade')
     OR EXISTS (SELECT 1 FROM public.sections WHERE name='TMP-Other-Section')
  THEN RAISE EXCEPTION 'Foreign school records leaked'; END IF;
END $check_owner$;
RESET ROLE;

-- Unknown identity sees no school structure, even with a JWT-like claim.
SELECT set_config('request.jwt.claim.sub',
  '00000000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
DO $check_unknown$
BEGIN
  IF (SELECT count(*) FROM public.campuses) <> 0
     OR (SELECT count(*) FROM public.academic_years) <> 0
     OR (SELECT count(*) FROM public.classes) <> 0
     OR (SELECT count(*) FROM public.sections) <> 0
  THEN RAISE EXCEPTION 'Unknown identity read academic records'; END IF;
END $check_unknown$;
RESET ROLE;

ROLLBACK;
