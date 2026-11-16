-- DB01 FIRST OWNER ACTIVATION TEMPLATE (ADMIN SQL EDITOR ONLY).
-- This is a privileged, one-time bootstrap operation and is NOT a migration.
-- Do NOT run before the reviewed DB01 migration is applied and tested.
-- Invitation must be issued from Authentication > Users > Send invitation,
-- accepted by the intended Owner, and email_confirmed_at verified.
-- Never insert directly into auth.users; never set a password through SQL.
--
-- Replace ALL REPLACE_... variables and review before execution.
-- The BEGIN/DO/COMMIT block rolls back as a unit if any condition fails.
BEGIN;

DO $bootstrap$
DECLARE
    v_owner_email text := 'REPLACE_WITH_OWNER_EMAIL';
    v_owner_name text := 'REPLACE_WITH_OWNER_DISPLAY_NAME';
    v_school_name text := 'Supa Model School';
    v_currency text := 'REPLACE_WITH_ISO_4217_CURRENCY';
    v_timezone text := 'REPLACE_WITH_IANA_TIMEZONE';
    v_campus_name text := 'REPLACE_WITH_FIRST_CAMPUS_NAME';
    v_owner_id uuid;
    v_school_id uuid;
    v_campus_id uuid;
BEGIN
    IF v_owner_email LIKE 'REPLACE_%'
       OR v_owner_name LIKE 'REPLACE_%'
       OR v_currency LIKE 'REPLACE_%'
       OR v_timezone LIKE 'REPLACE_%'
       OR v_campus_name LIKE 'REPLACE_%'
    THEN
       RAISE EXCEPTION 'Fill in every explicit Owner/school configuration value';
    END IF;

    IF v_owner_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       OR btrim(v_owner_name) = ''
       OR v_currency !~ '^[A-Z]{3}$'
       OR btrim(v_campus_name) = ''
    THEN
       RAISE EXCEPTION 'Invalid Owner or school configuration';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_timezone_names WHERE name = v_timezone
    ) THEN
        RAISE EXCEPTION 'Invalid IANA timezone';
    END IF;

    -- Serialize concurrent initial-Owner setup attempts.
    PERFORM pg_advisory_xact_lock(hashtext('supa_model_school_first_owner_bootstrap'));

    -- DB01 operates as one school per Supabase project. Fail if bootstrapped.
    IF EXISTS (SELECT 1 FROM public.schools)
       OR EXISTS (SELECT 1 FROM public.user_roles WHERE role = 'owner')
    THEN
       RAISE EXCEPTION 'This project already has school records or an Owner';
    END IF;

    SELECT id
      INTO v_owner_id
      FROM auth.users
     WHERE lower(email) = lower(btrim(v_owner_email))
       AND email_confirmed_at IS NOT NULL
       AND is_anonymous IS NOT TRUE
     LIMIT 1;

    IF v_owner_id IS NULL THEN
       RAISE EXCEPTION 'No matching verified invited Supabase Auth user';
    END IF;

    INSERT INTO public.schools(name, currency_code, timezone_name)
    VALUES (btrim(v_school_name), v_currency, v_timezone)
    RETURNING id INTO v_school_id;

    INSERT INTO public.campuses(school_id, code, name)
    VALUES (v_school_id, 'MAIN', btrim(v_campus_name))
    RETURNING id INTO v_campus_id;

    INSERT INTO public.user_profiles(user_id,display_name,is_active)
    VALUES (v_owner_id,btrim(v_owner_name),true)
    ON CONFLICT (user_id)
    DO UPDATE SET display_name = excluded.display_name, is_active = true;

    INSERT INTO public.user_roles(
      user_id,school_id,campus_id,role,is_active
    ) VALUES (v_owner_id,v_school_id,NULL,'owner',true);

    RAISE NOTICE 'First Owner provisioned. School: %, Campus: %, User: %',
      v_school_id, v_campus_id, v_owner_id;
END;
$bootstrap$;

COMMIT;

-- ADMIN-ONLY VERIFICATION AFTER BOOTSTRAP:
-- SELECT s.name, u.email, p.display_name, r.role, r.is_active,
--        (u.email_confirmed_at IS NOT NULL) AS email_verified
-- FROM public.schools s
-- JOIN public.user_roles r ON r.school_id = s.id
-- JOIN public.user_profiles p ON p.user_id = r.user_id
-- JOIN auth.users u ON u.id = r.user_id
-- WHERE r.role = 'owner';
