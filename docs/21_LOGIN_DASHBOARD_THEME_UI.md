# Login, dashboard and light/dark design — 2026-11-16

**Status:** Flutter source preview committed on branch `ui/login-dashboard-themes-20261116`; not built or tested in Flutter toolchain. No Supabase changes deployed.

## Visual reference
The four screenshots supplied by the school owner define the teal/green visual identity, wide Windows layout, narrow Android layout and management card structure. The preview uses native Flutter vector illustration as a **temporary stand-in** for the school/student photograph and bespoke crest. Do not add copyrighted/cropped pictures into the app without the owner's approved source assets.

## Implemented
- Responsive `LoginPage` with school/campus selection, username/email entry, masked password with toggle, remember-me checkbox, recovery/help placeholders and a separately labeled `Preview Dashboard` entry.
- Shared Material 3 design tokens: `SchoolTheme.light()`, `SchoolTheme.dark()`, `ThemeMode.system`, and on-screen theme menus.
- Adaptive `DashboardPage`: title and campus context, four stat cards, four quick actions, synthetic recent admissions, sample six-month trend, attendance, approvals and honest offline/sync warning.
- Existing Student Directory and Admission Wizard are reused from the shell; fee, attendance, expenses, reports and other modules remain feature previews.
- Desktop navigation rail and Android bottom navigation with More sheet.
- Global Search modal placeholder; no data is queried.

## Security boundaries
**The preview is not a sign-in solution.** Entering credentials never authenticates or stores a password. `Preview Dashboard` is explicitly a local read-only preview path; it MUST be disabled for production releases. Neither theme changes nor demo campus selection grant roles or permissions. `Sign In` and `Forgot Password` report that backend integration is incomplete.

DB01 already defines `schools`, `campuses`, `academic_years`, `user_profiles`, `user_roles`, `role_permissions` and campus read helpers. Do not duplicate them. The optional `DB05_UI_PREFERENCES.sql` draft adds per-user theme, compact navigation, authorized preferred-campus ID, shortcut order; every access is restricted to the current authenticated user with RLS.

### Real login sequence after backend readiness
1. User authenticates using Supabase Auth with email/password or a trusted, non-enumerating username resolution service.
2. Validate active `user_profiles` and active `user_roles` on the server.
3. Fetch **authorized** campuses only via existing DB01 RLS, then select active campus. The screenshot's pre-auth campus dropdown is a local sample. Do not expose the campus roster to unauthenticated clients.
4. Load academic year and school currency/timezone from authorized school context.
5. Fetch scope-authorized dashboard projections. Never trust client-selected campus UUID as permission.
6. Only show real Sync Now/Backup Now once device registration, authorization, encrypted offline storage, server receipts and backup adapters are complete.

### Dashboard read model still required
Build server-side aggregates **after** their underlying modules are tested. The projection contract should return:
- `campus_id` and `academic_year_id` plus school-wide totals only to explicitly authorized cross-campus roles.
- `student_count` from active, historically correct enrollments.
- `collected_minor_units`, `outstanding_minor_units` and six monthly collection buckets from immutable fee ledger (do not use floating point for money; prevent void/double-count errors).
- `attendance_present`, `attendance_absent`, `attendance_total` for the school's local current date and selected attendance session.
- Recent admissions based on approved finalized records, not pending applications.
- Approval counts by action permissions and campus scope.
- Last actual device sync acknowledgment and last verified backup restore point, not merely a client timestamp.
- Safe notification counters filtered to recipient and scope.

**Not yet designed/deployed:** attendance canonical source, fee ledger/receipts/discounts, expense approvals, payroll, notification inbox, searchable authorized indexes, per-campus dashboard read RPC and sync status adapter. Do not invent production rows or return demo figures from an RPC.

## Acceptance checklist for local Flutter/Android Studio
1. Run `flutter pub get`, `dart run build_runner build --delete-conflicting-outputs` (existing Drift), `flutter analyze`, `flutter test`.
2. Run `flutter run -d windows` and `flutter run -d <android-device-id>`.
3. Verify default screen is Login and `Sign In` never provides access.
4. Tap `Preview Dashboard` and confirm both mobile and wide layouts are readable without overflow.
5. Switch Light, Dark and System; check login, dashboard, Students and Admission Wizard.
6. Verify password visibility toggle; close and reopen demo; test navigation into Students and Admission Wizard.
7. Check no cloud credentials, network calls, fake actual sync or fee writes are issued.
8. Keep this screen **preview only** until real Auth/RLS/device validation is complete.

No Flutter SDK or Supabase local CLI is present in the assistant's execution environment, so compilation, widget tests, SQL migrations and live security checks remain explicitly unverified.
