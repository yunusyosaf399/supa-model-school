# DB10 Live Student Directory — Integration (2026-11-17)

## Deployed API
- Supabase project: `uebzvfzpbqqttbqyxxos`.
- Tracked migration: `20261117074122_db10_owner_student_directory_read_20261117`.
- PostgREST RPC: `public.owner_student_directory(p_school_id uuid,p_campus_id uuid,p_limit integer=100,p_offset integer=0)`.
- Only the signed-in, verified, active school Owner can fetch a requested campus's current-year enrollments. Underlying private function verifies Auth identity, active Owner profile and role, school/campus status, and returns a minimal student summary. No direct SELECT grants to authenticated student or guardian tables.
- Pagination supported in pages of up to 200. Flutter caps an in-memory load at 5,000 and fails closed beyond that; use server-side search/pagination before large-scale production usage.
- Do not add teacher/staff access by weakening the Owner authorization check. Introduce separately reviewed role-specific policies later.

## Live test result
- PostgreSQL test file: `supabase/tests/DB10_OWNER_STUDENT_DIRECTORY_INTEGRATION.sql` was executed on deployed function and passed (rollback-only).
- Existing fictional dataset: 32 active student enrollments in Main Campus.
- Verified Owner read: 32 student summaries.
- Offset pagination test: 10/32 requested.
- Unknown actor rejected; no guardian phone/date of birth included.
- School records unchanged by the verification query.

## Flutter integration
- New `StudentDirectoryRepository` uses `SupabaseClient.rpc('owner_student_directory')` with current authenticated session.
- Main Flutter app injects it when configured with `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
- When signed in, `StudentDirectoryPage` loads scoped live records. Loading, failures, and retry are visible; stale results are ignored. The unauthenticated preview keeps the separate synthetic four-student UI demo. Failed live requests never fall back to fabricated students.
- Student profile remains a read-only summary; guardians/documents, finance, attendance and detailed admissions are deliberately not exposed yet.

## Run on Windows
From project root with configured Flutter SDK:
```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/features/students/student_directory_live_widget_test.dart
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```
Do not put a service-role/secret key into Dart defines. Sign in as verified school Owner, choose **Students**, and confirm 32 fictional TEST records with correct class/section. No local authenticated Windows build was executed in this session.

## Still pending
- Real Flutter runtime CI and device integration.
- Role/campus tests with a second real campus and actual authenticated staff.
- Server-side search/pagination for larger schools, admission finalization, fee/attendance, encrypted offline cache and sync.
- Supabase Auth leaked-password protection warning should be reviewed: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
