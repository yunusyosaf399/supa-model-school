# Admission Edge Function — draft (NOT deployed; secure database functions deployed)

Path: `supabase/functions/admissions/index.ts`. **NOT DEPLOYED.**

**Updated 2026-11-16:** DB02 database tables, private admission SQL functions,
and a private deny-all document bucket are deployed to Supabase. This Edge
function is still source-only and cannot accept real requests until the
protected DB connection, authentication, and storage authorization tests pass.

**Mandatory approval:** The hardened database functions now require a
campus-scoped `principal` role to approve, return or reject. Owners and
super-admins can create drafts but cannot approve unless explicitly granted
the separate Principal role. Submission never directly creates a student.
Missing required documents require a reason and school-local deadline no more
than two calendar months ahead. Document upload/review is still unavailable.

See `supabase/migrations/20261116111638_db02_admission_private_operations_20261116.sql`
for the deployed function contract. Do not use the older
`DB02_ADMISSION_OPERATIONS.sql` draft because it predates these security rules.

This endpoint supports authenticated `POST` requests with an action:
- `save_draft`: school_id, campus_id, academic_year_id, application_id (nullable for creation), expected_revision (required for edits), operation_id, name, date_of_birth, previous_school, class_id, section_id, guardians[].
- `submit`: application_id, expected_revision, operation_id, conditional_due_on (when docs missing), conditional_reason.
- `review`: application_id, expected_revision, operation_id, decision (approve/return/reject), reason for return/reject.

The server must reject unauthenticated requests and always extract actor identity through `auth.getUser(jwt)`, then calls an unexposed, privileged SQL function with the validated actor UUID. The database independently checks role and campus and performs one atomic business operation. Reuse the same operation UUID for retries.

## Environment (server secrets, never commit actual values)
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` or legacy `SUPABASE_ANON_KEY`
- `SUPABASE_DB_URL` (protected **server-only** database connection)

Database connection: Deno PostgreSQL Pool 0.19.5, max one connection. Client dependency pinned to supabase-js 2.119.0. **Runtime compatibility is not yet verified.**

## Local validation
The SQL integration suite is `supabase/tests/ADMISSION_WORKFLOW_INTEGRATION.sql` (not executed). The static checker is `supabase/tests/check_admission_workflow.py`. Run SQL in a disposable LOCAL database and serve the Edge Function only after the migrations succeed.

## Required constraints
- `app_private` must NOT be an exposed Data API schema.
- SQL functions grant EXECUTE only to trusted server roles.
- No student PII, guardian contact details, JWT, database URL, or file path should appear in logs.
- Supply a real Authorization Bearer token; never accept `actor_id`, `role` or `approval` flags from request body.
- Do not enable in production before local SQL, security and double-submit concurrency tests pass.
- A future read API and document uploader are not in D03-T03 scope.

[Acceptance matrix](../../tests/ADMISSION_WORKFLOW_ACCEPTANCE.md).
