# Admission Edge Function — draft

Path: `supabase/functions/admissions/index.ts`. **NOT DEPLOYED.**

This endpoint supports authenticated `POST` requests with an action:
- `save_draft`: school_id, campus_id, academic_year_id, application_id (nullable for creation), expected_revision (required for edits), operation_id, name, date_of_birth, previous_school, class_id, section_id, guardians[].
- `submit`: application_id, expected_revision, operation_id, conditional_due_on (when docs missing), conditional_reason.
- `review`: application_id, expected_revision, operation_id, decision (approve/return/reject), reason for return/reject.

The server always extracts actor identity through `auth.getUser(jwt)`, then calls an unexposed, privileged SQL function with the validated actor UUID. The database independently checks role and campus and performs one atomic business operation. Reuse the same operation UUID for retries.

## Environment (server secrets, never commit actual values)
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY` or legacy `SUPABASE_ANON_KEY`
- `SUPABASE_DB_URL` (protected **server-only** database connection)

Database connection: Deno PostgreSQL Pool 0.19.5, max one connection. Client dependency pinned to supabase-js 2.119.0. **Runtime compatibility is not yet verified.**

## Required constraints
- `app_private` must NOT be an exposed Data API schema.
- SQL functions grant EXECUTE only to trusted server roles.
- No student PII, guardian contact details, JWT, database URL, or file path should appear in logs.
- Supply a real Authorization Bearer token; never accept `actor_id`, `role` or `approval` flags from request body.
- Do not enable in production before local SQL, security and double-submit concurrency tests pass.
- A future read API and document uploader are not in D03-T03 scope.

[Acceptance matrix](../../tests/ADMISSION_WORKFLOW_ACCEPTANCE.md).
