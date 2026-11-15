-- DB01 transactional RLS integration tests. LOCAL SUPABASE ONLY.
-- Prerequisites: DB01 schema applied locally and SEVEN fictional Auth users
-- created through LOCAL Supabase Auth before running this file.
-- This test is intentionally wrapped in BEGIN / ROLLBACK and does not
-- persist school fixtures. Run with psql -X -v ON_ERROR_STOP=1 -f <file>.
\set ON_ERROR_STOP on
\echo DB01 RLS TEST: running in an already initialized LOCAL database
BEGIN;
SET LOCAL statement_timeout = '30s';

CREATE TEMP TABLE sms_rls_actors (
  alias text PRIMARY KEY,
  user_id uuid NOT NULL UNIQUE
) ON COMMIT DROP;

INSERT INTO sms_rls_actors(alias, user_id)
SELECT wanted.alias, users.id
FROM (VALUES
  ('owner_s','sms-owner-s@example.invalid'),
  ('principal_a','sms-principal-a@example.invalid'),
  ('admin_a','sms-admin-a@example.invalid'),
  ('accountant_b','sms-accountant-b@example.invalid'),
  ('attendance_a','sms-attendance-a@example.invalid'),
  ('disabled_a','sms-disabled-a@example.invalid'),
  ('owner_t','sms-owner-t@example.invalid')
) AS wanted(alias,email)
JOIN auth.users users ON users.email = wanted.email;

DO $test$
BEGIN
  IF (SELECT count(*) FROM sms_rls_actors) <> 7 THEN
    RAISE EXCEPTION 'DB01 fixture requires 7 local Auth users with specified test emails (found %)',
       (SELECT count(*) FROM sms_rls_actors);
  END IF;
END;
$test$;

-- Allow the locally simulated authenticated role to resolve the test IDs.
GRANT SELECT ON sms_rls_actors TO authenticated;

INSERT INTO public.schools(id,name,currency_code,timezone_name)
VALUES
 ('11111111-1111-4111-8111-111111111111','SMS Test School','PKR','Asia/Karachi'),
 ('22222222-2222-4222-8222-222222222222','Other Test School','PKR','Asia/Karachi');

INSERT INTO public.campuses(id,school_id,code,name)
VALUES
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','A','Campus A'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','11111111-1111-4111-8111-111111111111','B','Campus B'),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','22222222-2222-4222-8222-222222222222','C','Campus T');

INSERT INTO public.academic_years(id,school_id,label,starts_on,ends_on,is_active)
VALUES (
 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 '11111111-1111-4111-8111-111111111111',
 '2026-27','2026-04-01','2027-03-31',true
);

INSERT INTO public.classes(id,school_id,campus_id,academic_year_id,name)
VALUES
 ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd','Grade 5'),
 ('ffffffff-ffff-4fff-8fff-ffffffffffff',
  '11111111-1111-4111-8111-111111111111',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'dddddddd-dddd-4ddd-8ddd-dddddddddddd','Grade 5');

INSERT INTO public.sections(id,class_id,name)
VALUES
 ('33333333-3333-4333-8333-333333333333','eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee','A'),
 ('44444444-4444-4444-8444-444444444444','ffffffff-ffff-4fff-8fff-ffffffffffff','A');

INSERT INTO public.user_profiles(user_id,display_name,is_active)
SELECT user_id,alias,(alias <> 'disabled_a') FROM sms_rls_actors;

INSERT INTO public.user_roles(user_id,school_id,campus_id,role)
SELECT user_id,
 CASE WHEN alias = 'owner_t' THEN '22222222-2222-4222-8222-222222222222'::uuid
   ELSE '11111111-1111-4111-8111-111111111111'::uuid END,
 CASE
   WHEN alias IN ('owner_s','owner_t') THEN null::uuid
   WHEN alias = 'accountant_b' THEN 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid
   ELSE 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'::uuid END,
 CASE
   WHEN alias IN ('owner_s','owner_t') THEN 'owner'
   WHEN alias = 'principal_a' THEN 'principal'
   WHEN alias = 'accountant_b' THEN 'accountant'
   WHEN alias = 'attendance_a' THEN 'attendance_staff'
   ELSE 'admin' END
FROM sms_rls_actors;

INSERT INTO public.school_settings(school_id,setting_key,setting_value)
VALUES
 ('11111111-1111-4111-8111-111111111111','test_school_setting','{"test":true}'::jsonb),
 ('22222222-2222-4222-8222-222222222222','test_school_setting','{"test":true}'::jsonb);

INSERT INTO public.campus_settings(school_id,campus_id,setting_key,setting_value)
VALUES
 ('11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','test_campus','{"value":1}'::jsonb),
 ('11111111-1111-4111-8111-111111111111','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','test_campus','{"value":2}'::jsonb);

INSERT INTO public.role_permissions(school_id,role,resource,action,permitted)
VALUES ('11111111-1111-4111-8111-111111111111','admin','admissions','read',false);

INSERT INTO public.principal_report_permissions(user_id,school_id,detail_campus_id,permitted)
SELECT user_id,'11111111-1111-4111-8111-111111111111',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true
FROM sms_rls_actors WHERE alias='principal_a';

INSERT INTO public.registered_devices(
  school_id,assigned_campus_id,registered_user_id,display_name,is_offline_enabled
)
SELECT '11111111-1111-4111-8111-111111111111',
 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',user_id,'Campus A main PC',true
FROM sms_rls_actors WHERE alias='admin_a';

-- Ensure a second simultaneous offline PC cannot be assigned to the same
-- campus. The expected unique violation must not abort the test transaction.
DO $test$
DECLARE blocked boolean := false;
BEGIN
  BEGIN
    INSERT INTO public.registered_devices(
      school_id,assigned_campus_id,registered_user_id,
      display_name,is_offline_enabled
    )
    SELECT '11111111-1111-4111-8111-111111111111',
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      user_id,'Improper second offline PC',true
    FROM sms_rls_actors WHERE alias='principal_a';
  EXCEPTION WHEN unique_violation THEN blocked := true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Duplicate active offline device accepted'; END IF;
END;
$test$;

-- Structural permission checks under the privileged fixture connection.
DO $test$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'schools','campuses','academic_years','classes','sections',
    'user_profiles','user_roles','role_permissions',
    'principal_report_permissions','school_settings','campus_settings',
    'registered_devices'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='public' AND c.relname=t AND c.relrowsecurity
    ) THEN
      RAISE EXCEPTION 'Missing RLS: %',t;
    END IF;
    IF has_table_privilege('authenticated',format('public.%I',t),'INSERT')
       OR has_table_privilege('authenticated',format('public.%I',t),'UPDATE')
       OR has_table_privilege('authenticated',format('public.%I',t),'DELETE')
    THEN RAISE EXCEPTION 'Unexpected direct client write privilege on %',t;
    END IF;
  END LOOP;
  IF has_table_privilege('anon','public.schools','SELECT') THEN
    RAISE EXCEPTION 'anon must not read schools';
  END IF;
END;
$test$;

-- School Owner S: both campuses, both sets of class/section and school-level
-- settings, but not the unrelated School T.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='owner_s'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.schools)<>1
    OR (SELECT count(*) FROM public.campuses)<>2
    OR (SELECT count(*) FROM public.classes)<>2
    OR (SELECT count(*) FROM public.sections)<>2
    OR (SELECT count(*) FROM public.school_settings)<>1
    OR (SELECT count(*) FROM public.campus_settings)<>2
    OR (SELECT count(*) FROM public.user_roles)<>6
    OR (SELECT count(*) FROM public.role_permissions)<>1
  THEN RAISE EXCEPTION 'Owner S RLS matrix failed'; END IF;
END;
$test$;
RESET ROLE;

-- Campus A Principal can see only Campus A operational rows. A cross-campus
-- reporting grant does NOT grant raw Campus B row access.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='principal_a'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.schools)<>1
    OR (SELECT count(*) FROM public.campuses)<>1
    OR (SELECT count(*) FROM public.classes)<>1
    OR (SELECT count(*) FROM public.sections)<>1
    OR (SELECT count(*) FROM public.user_roles)<>1
    OR (SELECT count(*) FROM public.principal_report_permissions)<>1
    OR (SELECT count(*) FROM public.school_settings)<>0
    OR (SELECT count(*) FROM public.campus_settings)<>0
    OR (SELECT count(*) FROM public.role_permissions)<>0
  THEN RAISE EXCEPTION 'Principal A RLS matrix failed'; END IF;
END;
$test$;
RESET ROLE;

-- Campus A Admin can view their own active registered desktop but not B.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='admin_a'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.campuses)<>1
    OR (SELECT count(*) FROM public.sections)<>1
    OR (SELECT count(*) FROM public.user_roles)<>1
    OR (SELECT count(*) FROM public.registered_devices)<>1
    OR (SELECT count(*) FROM public.principal_report_permissions)<>0
    OR (SELECT count(*) FROM public.school_settings)<>0
  THEN RAISE EXCEPTION 'Admin A RLS matrix failed'; END IF;
END;
$test$;
RESET ROLE;

-- Campus B Accountant must never see Campus A student-class references.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='accountant_b'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.campuses)<>1
    OR (SELECT count(*) FROM public.classes)<>1
    OR (SELECT count(*) FROM public.sections)<>1
    OR (SELECT count(*) FROM public.user_roles)<>1
    OR (SELECT count(*) FROM public.registered_devices)<>0
  THEN RAISE EXCEPTION 'Accountant B RLS matrix failed'; END IF;
END;
$test$;
RESET ROLE;

SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='attendance_a'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.schools)<>1
    OR (SELECT count(*) FROM public.campuses)<>1
    OR (SELECT count(*) FROM public.user_roles)<>1
  THEN RAISE EXCEPTION 'Attendance Staff A RLS matrix failed'; END IF;
END;
$test$;
RESET ROLE;

-- Inactive profiles must lose access to memberships and school/campus info.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='disabled_a'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.schools)<>0
    OR (SELECT count(*) FROM public.campuses)<>0
    OR (SELECT count(*) FROM public.user_roles)<>0
    OR (SELECT count(*) FROM public.principal_report_permissions)<>0
  THEN RAISE EXCEPTION 'Disabled profile RLS matrix failed'; END IF;
END;
$test$;
RESET ROLE;

-- Tenant T should see its own school/campus but no data of S.
SELECT set_config('request.jwt.claim.sub',
  (SELECT user_id::text FROM sms_rls_actors WHERE alias='owner_t'),true);
SET LOCAL ROLE authenticated;
DO $test$
BEGIN
  IF (SELECT count(*) FROM public.schools)<>1
    OR (SELECT count(*) FROM public.campuses)<>1
    OR (SELECT count(*) FROM public.classes)<>0
    OR (SELECT count(*) FROM public.user_roles)<>1
    OR (SELECT count(*) FROM public.school_settings)<>1
  THEN RAISE EXCEPTION 'Owner T tenant isolation failed'; END IF;
END;
$test$;
RESET ROLE;

\echo DB01 TEST ASSERTIONS PASSED. Rolling back all fictional school data.
ROLLBACK;
