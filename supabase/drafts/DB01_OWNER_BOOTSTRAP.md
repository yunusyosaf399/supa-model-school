# DB01 — First Owner bootstrap (admin-only procedure)

**Status: Instructions only. NOT executed.**

## Security premise
No ordinary user may choose their own role or campus. Create the first Owner through a privileged administrator after that user's identity exists in Supabase Auth. Never use user-editable JWT metadata for authorization.

## Local test setup
1. Create a fictional Owner account using the local Supabase Auth admin interface. Confirm its Auth UUID.
2. Record school name, currency and timezone. Currency and timezone are configurable, not hardcoded for the real school.
3. With the local administrator SQL console, begin a database transaction. Check that Auth UUID exists.
4. Insert the school, then two test campuses using its school UUID.
5. Insert an active user_profiles row referencing the verified Auth UUID.
6. Insert exactly one user_roles row with that user, school, campus_id NULL, role 'owner', and is_active true.
7. Verify IDs, relationships, and role; commit on success or rollback on failure.
8. Create fictional Principal, Admin, Accountant and Attendance Staff test identities. Assign a NON-NULL campus to each non-owner role using the trusted admin connection.

### Illustrative commands — privileged local database only

    BEGIN;
    -- Verify first: SELECT id, email FROM auth.users WHERE id = '<AUTH_UUID>';
    INSERT INTO public.schools (name,currency_code,timezone_name)
    VALUES ('Fictional Test School','PKR','Asia/Karachi')
    RETURNING id;  -- save SCHOOL_UUID

    INSERT INTO public.user_profiles(user_id,display_name)
    VALUES ('<AUTH_UUID>'::uuid,'Test School Owner');

    INSERT INTO public.user_roles(user_id,school_id,campus_id,role)
    VALUES ('<AUTH_UUID>'::uuid,'<SCHOOL_UUID>'::uuid,NULL,'owner');
    -- Add test campuses, check ownership/campus queries, then COMMIT.

The placeholders make this example intentionally not directly executable.

## Forbidden
- No service-role/secret credentials in Flutter, GitHub or the runbook.
- No self-service 'sign up as Owner' option.
- No public callable role-granting function.
- No live student data before successful RLS, audit, sync and backup tests.

## Remaining implementation
A trusted, audited Owner-managed user invitation, role change and revocation process is required. This document does NOT implement that service.