# D03-T03 — Admission workflow acceptance and threat matrix

**Code authored; NOT executed, deployed, end-to-end tested or production-ready.**
The workflow implements a private PostgreSQL transaction API for a trusted server plus an authenticated Supabase Edge Function draft.

## Workflow behavior

| ID | Case | Expected outcome |
|---|---|---|
| ADM-01 | Active Campus A Admin saves incomplete draft | Draft UUID returned, document requirements initialized |
| ADM-02 | Admin repeats same create operation UUID | Same draft ID returned; no second draft |
| ADM-03 | Admin updates draft with expected revision | Draft revised and event recorded |
| ADM-04 | Admin repeats successful update operation UUID | Original application returned, no conflict |
| ADM-05 | Admin updates with stale revision and NEW UUID | Conflict |
| ADM-06 | Same normalized name+DOB active application | Potential duplicate rejected for review |
| ADM-07 | Student from another school has identical name+DOB | No cross-school duplicate rejection |
| ADM-08 | Guardian list empty in draft | Allowed, submission later blocked |
| ADM-09 | More than one primary guardian | Rejected |
| ADM-10 | Submit without valid primary guardian telephone | Rejected |
| ADM-11 | Submit without requested class or DOB | Rejected |
| ADM-12 | Birth certificate requirement missing | Rejected |
| ADM-13 | Previous school supplied but transfer requirement absent | Rejected |
| ADM-14 | Required documents uploaded but not verified | Conditional deadline still required |
| ADM-15 | Missing documents and no deadline or reason | Rejected |
| ADM-16 | Missing documents, deadline and reason supplied | Conditional submission permitted |
| ADM-17 | Document deadline earlier than school-local today | Rejected |
| ADM-18 | Principal approval disabled by Owner | Admin submission finalizes student in atomic operation |
| ADM-19 | Principal approval enabled | Submission enters pending; no student yet |
| ADM-20 | Principal of correct campus approves pending | Student/guardians/enrollment created, audit recorded |
| ADM-21 | Principal from different campus approves | Denied |
| ADM-22 | Accountant or Attendance Staff attempts any draft/review | Denied |
| ADM-23 | Principal returns with reason | Returned state; no student created |
| ADM-24 | Admin revises returned draft and resubmits | Valid new submission |
| ADM-25 | Principal rejects with reason | Rejected and audit retained, no student |
| ADM-26 | Principal approval retried with same operation UUID | One student/enrollment; original result returned |
| ADM-27 | Two concurrent approvals | Row lock permits exactly one student |
| ADM-28 | School-wide registration counter concurrent admits | Sequential unique registration, no collision |
| ADM-29 | Student with same name+DOB already enrolled | Duplicate detected; do not create second student |
| ADM-30 | Approved conditional admission deadline expires | Still enrolled; overdue alert belongs to later reporting task |
| ADM-31 | All required docs verified during pending approval | Current completeness becomes complete; audit persists |
| ADM-32 | Same operation UUID reused on another action | Rejected |
| ADM-33 | Direct anon/authenticated call to private functions | Denied; never expose app_private schema via Data API |
| ADM-34 | Edge HTTP request with invalid Auth token | 401; no DB mutation |
| ADM-35 | Authenticated user attempts to spoof actor_id in payload | Ignored; verified Auth user ID used |
| ADM-36 | Input contains SQL syntax in student name | Parameterized, treated as text; never executed as SQL |
| ADM-37 | Financial settings not ready | Admission does not post any fee or cash movement |
| ADM-38 | SQL failure after student insert but before enrollment | Entire statement/transaction rolled back |
| ADM-39 | Document Storage not configured | Existing file upload/verify actions not available, conditional path remains design |
| ADM-40 | Offline Windows draft operation | Requires later DB04 durable outbox, not implemented by this task |

## Strict boundaries
- DB01/DB02 migrations must pass before running workflow SQL.
- Owner setting key `admissions_principal_approval` is JSON boolean and remains Owner-controlled.
- Any real document verification must come from a future authorized file service. Never mark an upload verified merely because an object path exists.
- The Edge function needs the protected server `SUPABASE_DB_URL` environment variable; never place it in GitHub or Flutter assets.
- SQL functions use p_actor **only after Edge verified the token**; calling those functions from an untrusted public RPC is forbidden.
- Registration generator code is authored as part of the finalization transaction; D05-T03 runtime correctness remains pending.
- Duplicate child detection by same name+DOB is a conservative guard, not a definitive person identifier. A school-authorized exception process will be required for legitimate same-name/DOB children.
- SQL code has **NOT** been executed in PostgreSQL; Edge runtime and concurrency are NOT verified.

The repository also includes `supabase/tests/ADMISSION_WORKFLOW_INTEGRATION.sql` containing executable SQL assertions under a single ROLLBACK transaction. It has **not** been executed. Use fictional local Auth identities described in the SQL header.

## Local test order (when laptop is available)
1. Run verified local DB01 migration and two-campus RLS tests.
2. Run reviewed DB02 base migration.
3. Apply reviewed `DB02_WORKFLOW_SCHEMA.sql` and `DB02_ADMISSION_OPERATIONS.sql` as separately generated local migrations.
4. Seed ONLY fictional users for Owner, Admin A/B, Principal A/B, Accountant.
5. Set Owner approval policy and exercise ADM-01 through ADM-38.
6. Serve Edge Function locally with environment secrets supplied out of repository; verify real authenticated calls.
7. Record detailed pass/fail evidence, run Supabase security advisors, then review PR for possible merge/deployment.
