# DB10 — Live Admission Draft Saving (2026-11-17)

## Deployed
Supabase migration `20261117080615_db10_owner_admission_draft_20261117`.
Public authenticated RPC: `owner_save_admission_draft`. It is SECURITY INVOKER and delegates to a private SECURITY DEFINER operation. The actor is ALWAYS derived from `auth.uid()`; no client-provided user ID is accepted. Active verified school Owner membership and school/campus/year/class/section identity are rechecked in the database. No direct child/admission table grant has been given.

The operation calls the already-deployed `app_private.admission_save_draft` implementation, which enforces idempotency, revision checks, duplicate active-child checks, guardian entry validation, creates birth/transfer document placeholders and audit events. Returns application UUID, revision and `draft` state.

## Windows + Android Flutter
A new `AdmissionDraftRepository` uses the authenticated Supabase client. Save Draft buttons are enabled only in an Owner context with a repository configured, and validate name and authorized campus/year/class. Saving supports new drafts and repeated edits to the same draft within one wizard session. On uncertain network failure, the exact request UUID and payload are reused to avoid duplicate writes. Flutter shows a clear confirmation/error. Leaving a saved draft does not delete the server record.

Fields persisted by DB02 **today**: applicant name, date of birth, previous school, academic year/campus/class/section, guardian names/relationships/phone/primary/legal flags. Document status rows are created as MISSING only. Existing UI contains additional information (religion, nationality, gender, transport, discounts, notes, conditional deadline, etc.) **which is NOT saved by this endpoint**. Do not present it as fully persisted.

## Verified
- Rollback-only `DB10_OWNER_ADMISSION_DRAFT_INTEGRATION.sql` against live Supabase passed: create + missing-document placeholders + audit, same-operation idempotency, update revision 1 to 2, stale revision rejection, unknown actor denial; no additional student records.
- Five existing fictional admission drafts and 32 enrolled students remain unchanged after rollback.
- Flutter widget regression tests and analyzer run through GitHub Actions. Device launch and signed-in HTTP RPC end-to-end are separate gates.

## Not enabled by this increment
- Actual document uploads/verification and Conditional Admission deadline persistence
- Submission to Principal, return/approve/reject, final student record creation
- Resume/edit previously saved applications in a later app session
- Parent access, bank receipts, fee posting, offline admissions sync
- Role-specific Principal tests and multi-campus segregation

These are intentional guardrails. Do not enable approval or finalization until the corresponding authorization and audit tests pass.
