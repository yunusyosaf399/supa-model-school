# DB01 — two-campus RLS manual test plan

**Status: NOT RUN.** The SQL draft must first execute successfully on local PostgreSQL.

## Fixture identities
- School S, Campus A and B, an academic year, a class and section per campus.
- Owner O (school-wide role, campus NULL).
- Principal P_A (Campus A), Admin A_A, Accountant AC_B, Attendance Staff AS_A.
- Disabled profile DISABLED_A (Campus A).
- Optional unrelated School T and Campus T.
Use fake identities in a local database and keep credentials out of GitHub.

## SQL-only check template (trusted local session)

    BEGIN;
    SET LOCAL ROLE authenticated;
    SELECT set_config('request.jwt.claim.sub','<TEST_AUTH_UUID>',true);
    SELECT auth.uid();
    SELECT id,name FROM public.schools;
    SELECT id,school_id,code FROM public.campuses;
    SELECT school_id,setting_key FROM public.school_settings;
    SELECT role,school_id,campus_id FROM public.user_roles;
    ROLLBACK;

The SQL-only fake JWT is ONLY an internal trusted local test. Also verify with real authenticated Data API requests; do not mistake a simulated claim for something the public client can forge.

## Expected read results
| Role | schools | campuses | school_settings | user_roles |
| --- | --- | --- | --- | --- |
| Anonymous | none/API denied | none/API denied | denied | denied |
| Owner O | School S | Campuses A and B | Owner's school keys | memberships in S |
| Principal P_A | School S | Campus A only | no rows | own role |
| Admin A_A | School S | Campus A only | no rows | own role |
| Accountant AC_B | School S | Campus B only | no rows | own role |
| Attendance AS_A | School S | Campus A only | no rows | own role |
| Disabled user | no school data | no campus data | no rows | own role can still be visible: review pending |
| Unrelated School T | School T only | Campus T only | none unless Owner T | own role |

## Mandatory negative cases
- An ordinary user cannot INSERT, UPDATE or DELETE any DB01 role, settings, device, school or campus record.
- An ordinary user cannot make themselves Owner or move assigned campus.
- Class and section queries return records only for permitted campuses.
- The Principal's detail permission record does not automatically expose raw cross-campus financial data.
- A suspended profile cannot view school/campus data through the access helpers.
- Role removal and device revocation require online revalidation (offline enforcement is a separate feature).
- Tests must cover app auth APIs, not just a superuser SQL session.

## Completion evidence
Do not mark D02-T03 or D02-T04 complete until migration executes, auth fixtures exist, two-campus positive/negative policies pass, and test evidence is recorded (date, CLI version, fixture IDs, outcomes, advisor findings).