# First Owner activation, Flutter login and Owner Control Panel

**Updated:** 2026-11-16

## Hosted status — ACTIVATED
- Project: Supa Model School, Supabase project `uebzvfzpbqqttbqyxxos`.
- Existing Auth identity was verified (confirmed email, not deleted, not anonymous); no password was read or changed.
- One school record `Supa Model School`, one first campus, one active profile and one active **school-wide Owner** role (`campus_id = NULL`) were created atomically through privileged SQL.
- The DB01 migration `20261116051446_db01_foundation_owner_access_20261116` was applied successfully.
- **12/12** DB01 exposed tables had RLS enabled at verification.
- Positive Owner vs negative unknown-user RLS checks passed, including transaction-only test fixtures and live seeded owner. This is a focused smoke test, **not** the full seven-user integration catalog.
- A dedicated `initial_setup` settings record marks school details still pending.
- No real student, finance, attendance, payroll, admission or offline-sync data was generated.

## Temporary initial setup
The user has not specified the real school currency, timezone or campus name. Rather than guessing, activation used:
- Currency: `XXX` (ISO 4217 no currency), **not final**.
- Timezone: `Etc/UTC`, **not final**.
- First campus display name: `Main Campus (Setup Pending)`, **not final**.
- Academic year: **not yet created**; no year should be invented.
- Finance and attendance entry must remain disabled until actual settings are supplied and respective domain migrations pass.

## Flutter source on auth/first-owner-bootstrap-20261116
- `lib/features/auth/data/owner_auth_gateway.dart`: Supabase email/password sign-in, `getUser()` validation, active profile, exactly one active school-wide Owner role, active school, RLS-authorized active campus query, sign-out and password update with current password.
- `lib/main.dart`: Supabase public/publishable key through Dart defines; Owner-gated shell; debug design preview separate. `EmptyLocalStorage` means tokens are not persisted across app restarts pending encrypted storage.
- `lib/features/auth/presentation/login_page.dart`: live sign-in errors, actual campus choices only after authentication, password recovery still unavailable pending redirect setup.
- `lib/features/owner/presentation/owner_control_panel_page.dart`: Owner-specific Settings view, read-only setup state and change-password form; clear credentials after success and require a new sign-in.
- `test/features/auth/owner_auth_widget_test.dart`, `test/features/owner/owner_control_panel_widget_test.dart`: synthetic gateway/widget test sources, **not run** in assistant environment.
- `supabase/migrations/20261116051446_db01_foundation_owner_access_20261116.sql`: mirrors the exact hosted migration version for reproducibility. School-specific Owner data must not be replayed as a migration on new projects.
- `supabase/drafts/DB01_FIRST_OWNER_ACTIVATION_TEMPLATE.sql`: template for a new school project with an already verified Auth user. It is NOT to be run again on this project.

## How to run Windows preview with LIVE Owner sign-in
In PowerShell:

```powershell
git fetch origin
git switch auth/first-owner-bootstrap-20261116
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test

flutter run -d windows `
  --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=PASTE_PROJECT_PUBLISHABLE_KEY_HERE
```

Get the publishable client key from your project dashboard **Project Settings → API Keys**. Do not use the service-role or secret key in Flutter or GitHub.

Sign in with the password you created in Supabase Auth. The installed app has a functioning authentication path in source, but **no real password-based UI session has been exercised or independently verified** here.

In the authorized Owner shell, open **Settings** from navigation (or **More → Settings** on Android). The password-change operation uses Supabase Auth `updateUser(UserAttributes(password: ..., currentPassword: ...))`, not a school database password field. Changing a password requires the current password and logs the user out on success.

## Security audit observations
The Supabase security advisor reported one WARNING: leaked-password protection disabled. See https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection. Enable if available for the project plan. No missing-RLS advisor findings were returned.

Required before real school operation:
1. User confirms campus name, actual currency, timezone and academic-year dates.
2. Build audited Owner-only update pathway for school/campus settings and mark initial setup complete.
3. Run full seven-user/two-campus negative RLS tests on local staging (existing SQL test includes seven fictional Auth identities).
4. Finalize Auth sessions (encrypted storage), account recovery deep-links, MFA/password policy and user-management authorization.
5. Deploy/test DB02 admissions, finance and attendance domain migrations and authorized projections, then replace all fictional dashboard data.

**GitHub PRs remain draft**; Flutter compilation, analyzer/widget tests and release validation require local Windows/Android SDK execution. No GitHub Actions workflows were created.
