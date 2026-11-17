# Admissions — live Windows/Android acceptance checklist

Updated 17 November 2026. Supa Model School project `uebzvfzpbqqttbqyxxos`.

## Implemented
1. Owner signs in through Supabase Auth; a confirmed, active Owner role is required.
2. Owner opens Admissions, which shows live applications across Draft, Submitted, Returned, Approved and Rejected states with search and status filters. Only Draft/Returned can be resumed.
3. Owner creates a draft with student name, DOB, campus, year, class, section, primary guardian name and phone. Save Draft persists core fields, a revision, audit events, and required certificate placeholders.
4. In Documents, owner chooses a PDF/JPG/PNG/WebP up to 10 MiB. Bytes go to the private `sms-admission-documents` bucket under UUID-based paths. Upload history is registered. A successful upload changes status to **uploaded**, not verified.
5. Owner forwards to the assigned Principal. Unverified/missing applicable required certificates require a reason and deadline no later than two calendar months in the school's local timezone.
6. Only a different authenticated, confirmed, active Principal assigned to that campus can inspect the current private certificate using a 60-second signed link, verify/reject an uploaded version, and approve/return/reject a submitted admission.
7. Principal approval performs atomic student + active enrollment + guardian creation in DB02, with audit logging and school-wide registration identifier. A rejected/returned admission does not create a student.
8. Owner sees updated status in Admissions; the registered student appears in Student Directory after its refresh.

## Test on Windows
```powershell
git checkout main
git pull origin main
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Sign in as the verified Owner, not Preview. Open Admissions, create a **TEST** application with accurate placement and one primary guardian, save draft, upload a harmless synthetic test PDF, confirm Upload status and revision, choose a conditional deadline if some required certificates are unverified, then submit. Verify the application is Pending Principal rather than disappearing or showing as enrolled. Use the separate Principal account to review and approve; refresh Students and Admissions.

## Principal account setup (required for device acceptance)
The live school currently has **zero permanent Principal accounts**. The SQL tests create temporary identities only and roll them back. Use **two different Auth accounts**: Owner for submissions, Principal for approval. Do not assign the Owner Principal role.

An authorized Supabase administrator must:
- Invite/create a separate Principal through Supabase Dashboard > Authentication > Users. The invited Principal confirms their email and sets a strong password.
- Record the Principal's Auth UUID.
- Create an active `public.user_profiles` record for that UUID and an active `public.user_roles` mapping with `role='principal'`, matching the existing school and assigned campus UUID. Do this only through the authenticated administrative provisioning process. Do **not** set roles using editable JWT user metadata.
- Verify the Principal has no Owner or Super Admin role at that school.
- Confirm `public.principal_session_context()` returns only the assigned campuses under that Principal's authenticated session.
- Sign in with the Principal account using the app's normal login page. It will route to a separate Principal Admissions workspace; no Owner navigation is granted.

For current school test fixtures, school UUID `aaa87efd-ba04-43e1-9fe6-7ad8d6cac654`, campus UUID `e2308d36-ff0d-438d-97b4-95ed6d4c13c6`. These are **test-only** IDs; do not reuse for another installation.

## Current limits — do not treat as production-ready
- Supabase operations and Flutter widgets are database-tested and CI-tested. Actual signed-in Windows/Android HTTP upload, external PDF/image viewer, Principal sign-in and final approval have **not** been performed on your devices yet.
- Incoming file signatures are checked on the Flutter client, not independently scanned for malware or verified from actual Storage bytes on the server. Human review is mandatory.
- Application form fields beyond the DB02 draft core (e.g. gender, nationality, extra notes, discount and transport selections) are **not persisted by the current draft contract**; fee posting is a separate future module.
- A device restart can lose pending upload registration, leaving an orphan object to reconcile.
- Offline encrypted admission cache and sync are not implemented.
- Real Principal invitation/provisioning is an administrator-controlled operation; no public/self-grant invitation exists in Flutter.
- Student documents approved into the archive may require a separate authorized historical document access module.

## Automated checks
`supabase/tests/DB10_PRINCIPAL_APPROVAL_INTEGRATION.sql` — Owner submission, conditional deadline, Principal identity, stale revision rejection, atomic student creation, rollback.

`supabase/tests/DB10_PRINCIPAL_DOCUMENT_REVIEW_INTEGRATION.sql` — file version integrity, Principal inspection authorization, Owner denial, audit, rollback.

`supabase/tests/DB10_PRINCIPAL_SESSION_CONTEXT_INTEGRATION.sql` — verified Principal session lookup, Owner denial, temporary identity rollback.

`supabase/tests/DB10_OWNER_ADMISSION_REGISTRY_ALL_STATUSES_INTEGRATION.sql` — submitted applications remain visible to Owner without private document paths.

No real student or credential was created by these tests.
