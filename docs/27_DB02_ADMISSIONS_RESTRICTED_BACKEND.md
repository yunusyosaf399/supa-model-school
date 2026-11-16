# DB02 Admissions — Deployed Restricted Foundation and Principal-Only Operations

**Date:** 2026-11-16  
**Project:** Supa Model School, Supabase ref `uebzvfzpbqqttbqyxxos`  
**Branch:** `db/db02-admissions-secure-foundation-20261116`  
**Dependencies:** stacked login/auth/academic/admission-lookup PRs #14–#17.

## Deployment summary

DB02 is deployed in **three independently tracked Supabase migrations**:

| Version | Name | Deployed scope |
| --- | --- | --- |
| `20261116111057` | `db02_admissions_restricted_schema_20261116` | 10 DB02 identity/document/enrollment tables + 3 workflow tables |
| `20261116111638` | `db02_admission_private_operations_20261116` | Hardened private draft/submit/Principal review/finalization SQL functions |
| `20261116111943` | `db02_private_document_bucket_20261116` | Private `sms-admission-documents` Storage bucket with 10 MiB limit / MIME allowlist; no client object access |

All three exact migration versions are mirrored under `supabase/migrations/`.

**No real admission has been created.** The live school still has initial
setup pending and zero academic-year rows, so trusted admission functions
reject attempts to save real drafts until real configuration is complete.

## Data model

The 13 RLS-enabled `public` tables:

1. `students` — permanent school-scoped registrations after Principal approval
2. `guardians` — existing school-specific parents/guardians
3. `student_guardians` — school-contained relationship/primary contact
4. `admission_applications` — draft, submitted, returned, rejected, approved
5. `student_documents` — birth/transfer requirements, conditional due dates
6. `student_document_uploads` — immutable upload-version metadata
7. `student_document_reviews` — immutable document verification events
8. `admission_document_deadline_events` — audited due-date decisions
9. `student_enrollments` — class/section/academic-year placement
10. `campus_transfer_requests` — future campus transfer workflow
11. `admission_application_guardians` — draft guardian identities
12. `school_registration_counters` — serialized school-wide registration IDs
13. `admission_action_events` — immutable workflow action/idempotency log

All 13 have **RLS enabled and NO Data API client grants/policies**. This is
intentional deny-by-default, not a missing authorization implementation.
Do not add blanket authenticated SELECT/INSERT on student PII tables.

## State machine and roles

- Owner or a campus Admin may create/update a draft through a **trusted
  server-side operation**. Admin access must match the application's campus.
- Draft validates the school/active academic year, duplicate name + DOB
  candidate, guardians, class/section FK, and idempotent operation UUID.
- Birth certificate is always required; transfer/leaving certificate is
  required when a previous school is recorded.
- Missing certificates can be conditionally submitted if the reason is at
  least four characters and the deadline is between school-local today and
  **two calendar months ahead**, inclusive.
- **Every submission is forwarded to the Principal.** It creates NO student.
  There is no optional Owner setting that can bypass Principal approval.
- Only an active campus `principal` membership can approve, return or
  reject. Return/reject must have a reason. School-wide Owner or super-admin
  alone cannot approve.
- Approval atomically creates the permanent student, unique school-wide
  registration number, guardian relationships, class/year/section enrollment,
  document links and audit event. No fees are charged here.
- A returned application can be revised and resubmitted. A rejected
  application creates no student.
- Duplicate operation IDs are idempotent for successful retries. Revised
  drafts use optimistic revision control; approval uses a row lock.
- Conditional admission remains enrolled after deadline expires. Overdue
  is derived from school-local date; **never auto-delete/withdraw** a student.
- Sensitive document object keys are not accessible to Flutter yet.

## Privilege boundary

Operations live in the non-exposed `app_private` schema:
`admission_save_draft`, `admission_submit`, `admission_review`,
`admission_finalize`, authorization and principal-required helpers.

Their EXECUTE permission is **service_role only**, with all
anon/authenticated/PUBLIC grants revoked. This means the Flutter client cannot
call these operations directly through PostgREST. The existing
`supabase/functions/admissions/index.ts` is an **undeployed draft**
server endpoint that must verify the Supabase Auth JWT and pass its verified
actor to the database over a protected DB connection.

The database role check is independent of client input, and only a
trusted server holding `SUPABASE_DB_URL` can invoke the operations.
Do not commit database URLs, service-role/secret keys, or actual user passwords.

## Document bucket

`sms-admission-documents` is configured:
- `public = false`
- `file_size_limit = 10485760` (10 MiB)
- MIME allowlist: PDF, JPEG, PNG, WEBP.
- No anonymous/authenticated `storage.objects` permissions were added.
- No actual files or metadata upload entries exist.

This intentionally **does not complete document uploading**. The future
server-side upload flow must enforce actual file signatures/limits, malware
handling as needed, immutable Storage object paths, versioned metadata, proper
staff campus/document authorization, signed download URLs, and verified
review events. Merely creating the bucket or inserting a file path must not
mark a certificate verified.

## Verification executed on hosted Supabase

- Rollback-only schema test passed: 13 public tables; all have RLS; no
  client student/document access grants.
- Rollback-only private SQL test passed:
  1. Unrecognized actor cannot create an admission draft.
  2. Owner draft creates requirement rows and repeated operation is idempotent.
  3. Conditional due date beyond two months is rejected.
  4. Submission results in `pending` Principal review and zero students.
  5. Owner without Principal role cannot approve.
  6. A **temporary Principal role assignment inside the rollback transaction**
     exercised approval and atomically created a student, guardian link,
     enrollment, document links and audit.
  7. Retried approval did not create a duplicate student.
- Bucket creation was tested with rollback; then migration deployed.
- Final hosted state confirmed: zero students, guardians, applications,
  enrollments, action events, and academic years; `initial_setup=pending`.
- Security Advisor INFO: 13 tables have RLS without policies, intentionally
  denying all client data access. Previous Auth leaked-password-protection
  warning remains; investigate if the current plan permits enabling it.
- **No fake Auth user was inserted on live Supabase.**

## Outstanding required work before real admissions

1. **Owner user completes real school setup, then Academic Setup creates
   campus/class/section masters.**
2. Configure a real Principal Auth account with a campus-scoped verified
   role (Owner has no implicit Principal rights).
3. Implement and deploy the authenticated trusted admission server endpoint,
   including secure server DB connection and HTTP/rate-limit/security tests.
4. Implement the private document upload/version/review service and signed
   download authorization, validate real bytes and storage access.
5. Implement explicit, RLS-safe and privacy-conscious read projections for
   Principal approvals and Admin intake lists.
6. Test real Principal/Admin sessions, review/return/reject, concurrent
   approval and collision handling, plus full multi-campus negative tests.
7. Connect Flutter with a real intake API and enable Submit **only after**
   these gates pass; current wizard remains preview and does not save child PII.
8. Run Flutter analyzer/widget tests on the user's Windows/Android workspace
   (Flutter SDK not available in assistant environment).

## GitHub test/source files

- `supabase/tests/DB02_LIVE_ROLLBACK_PRINCIPAL_APPROVAL.sql`
- `supabase/migrations/20261116111057_db02_admissions_restricted_schema_20261116.sql`
- `supabase/migrations/20261116111638_db02_admission_private_operations_20261116.sql`
- `supabase/migrations/20261116111943_db02_private_document_bucket_20261116.sql`
- `supabase/functions/admissions/README.md`

**Do not run the rollback-only test against a school that already has live
students or academic years:** it assumes a single empty initial school and
aborts before writing when that precondition fails.
