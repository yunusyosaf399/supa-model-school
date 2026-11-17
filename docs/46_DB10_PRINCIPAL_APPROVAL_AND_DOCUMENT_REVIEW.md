# DB10 — Principal-gated Admission Submission, Verification and Finalization

**Date:** 2026-11-17  
**Live Supabase project:** `uebzvfzpbqqttbqyxxos`  
**Role readiness:** The currently provisioned school has exactly one **Owner** account and **zero Principal** accounts.

## Deployed database migrations
- `20261117143622_db10_principal_admission_submit_review_20261117.sql`
- `20261117144550_db10_principal_document_verification_20261117.sql`

### Owner intake submission
`public.owner_submit_admission(application_id,revision,operation_id,conditional_due,conditional_reason)` binds the caller to `auth.uid()`. It requires an active verified Owner, reuses DB02 `admission_submit`, and requires the saved applicant DOB, academic placement, exactly one primary guardian with a valid phone, and applicable document requirements. Unverified required documents require a reason and deadline no more than **two calendar months** from the school's local submission date. This logs document deadline decisions and queues `approval_state=pending`; **no student is created**.

### Principal review
`public.principal_admission_queue(school_id,campus_id,limit,offset)` is visible exclusively to an active verified Principal assigned to that campus, and only for pending submissions they did not create. It excludes guardian contact and certificate file paths.

`public.principal_review_admission(application_id,revision,operation_id,decision,reason)` accepts `approve`, `return` or `reject`. It refuses Owners, Super Admins, application creators, staff from other campuses, unknown actors, stale revisions or missing return/rejection reasons. Only **approval** calls DB02's atomic `admission_finalize`, which creates the student, active enrollment and linked guardians and sets a school-wide registration number. Return/reject does **not** create a student.

### Principal certificate inspection and review
`public.principal_document_review_list(application_id)` returns document IDs, current registered upload versions and private file paths only for authorized pending Principal reviews.
`storage.objects` has a new **SELECT-only** RLS policy scoped to these exact files and campuses; existing Owner-only INSERT policy remains unchanged.
`public.principal_review_admission_document(document_id,revision,operation_id,decision,reason)` records an append-only document review against a matching registered file version, with idempotent operation UUID, optimistic revision and verified/rejected state. It does not permit reviewing missing or unregistered files. No upload is automatically considered verified.

**Never use the Supabase secret/service role key in Flutter.**

## Flutter integration
- Existing Windows/Android Admission Wizard now has authenticated **Submit for Approval** with review confirmation, conditional deadline validation and idempotent retry.
- A separate `PrincipalApprovalPage` displays the authorized pending queue, and has Approve, Return and Reject actions.
- `PrincipalDocumentsPage` lets a Principal open a **60-second signed HTTPS** link with the default system document viewer before the Verify/Reject buttons become available.
- This Principal UI is intentionally **not linked into the Owner shell**. The current Flutter authentication gateway only permits verified Owners. A separately reviewed Principal sign-in/role-selection router and a properly provisioned Principal account are required for a real end-to-end device test.

## Verification completed
- SQL integration scripts run against connected Supabase inside BEGIN/ROLLBACK transactions.
- A temporary Principal Auth identity/role was created in the test transaction only, the Owner submitted a conditional application, Principal queue/access were verified, Owner approval denied, stale revisions rejected and Principal approval created exactly one new student/enrollment. All fixture data was rolled back.
- Certificate review test creates a synthetic Storage *metadata* object, checks denied Owner access/allowed Principal access, current registered version verification, idempotency and audit, then rolls back. It does **not** prove an actual HTTP upload or human certificate inspection.
- PostgreSQL and Flutter CI validation are required before merge. No actual school student or document should change as a result of these tests.

## Pending production acceptance gates
1. Provision an actual independently authenticated Principal for each campus and build a role-specific Principal login/router.
2. Launch Windows and Android, sign in as Owner and Principal, perform real upload/inspection, conditional submission, approval and refresh in Student Directory.
3. Server-side file inspection/malware validation is not implemented; a human Principal review with client file-signature validation is not a substitute for scanning.
4. Offline admissions sync and recovery of in-progress upload/approval operations after process restart require independent design and testing.
5. More extensive cross-campus, disabled/expired role, concurrent review, returned-application resubmission and failed external viewer tests.
