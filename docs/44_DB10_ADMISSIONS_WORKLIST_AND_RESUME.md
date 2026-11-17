# DB10 — Saved Admissions Worklist and Resume (17 Nov 2026)

## Backend
New live migration: `20261117122713_db10_owner_admission_worklist_20261117`.
Public RPC `owner_admission_worklist(school_id,campus_id,limit,offset)` is a SECURITY INVOKER wrapper. Private SECURITY DEFINER function binds the actor to `auth.uid()`, verifies active/confirmed Owner role and active campus/school, and returns `draft`/`returned` applications only, with revision, guardian input fields and document statuses. No storage paths, files, verification controls, approved student details, or arbitrary table grants.

The live rollback-only integration test passed for the existing five fictional admissions, pagination (2/5), document metadata and rejecting an unknown user. No live application was updated during testing.

## Flutter
Authenticated Admissions tab now shows the campus-scoped worklist with retry/loading, missing document counts and a Resume action. The existing wizard restores only persisted DB02 data: name, DOB, previous school, academic class/section, guardians and revision. The Save Draft operation on a resumed item updates that same application with optimistic revision checking; it does not create a new application. Historical-year records are visible but not editable in the current-year wizard.

Current wizard fields **not saved by the DB02 draft contract** include gender, nationality, other contact details, admission fee preferences, transport, notes, document deadlines and document bytes. Unsaved details are not restored.

## Security and rollout gates
1. Existing private bucket `sms-admission-documents` remains deny-all with no direct client upload/download grants. Adding a Storage policy to work around this is not permitted. Next feature requires authenticated, per-document signed upload/read capabilities, MIME/size validation and immutable version metadata.
2. Submit/Principal review and student finalization are still restricted to internal private service operations. A verified Principal account and cross-campus role/approval fixtures must be tested before exposing review. Owner cannot self-approve.
3. Test actual login and UI on Windows and Android separately from CI widget tests; CI does not exercise real user session or object Storage.
4. Device offline admission cache and encrypted sync are not implemented.
5. Remaining app and security limitations should be presented in the interface without claiming final admission is complete.

## Test locally
```powershell
git pull origin main
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/features/admissions/admission_worklist_widget_test.dart
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```
Use a **publishable** key, never the service-role/secret key.
