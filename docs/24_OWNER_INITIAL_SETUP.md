# Owner Initial School Setup — Flutter + Supabase

Date: 2026-11-16
Branch: `auth/first-owner-bootstrap-20261116`
Stacked draft PR: #15 (depends on theme/login PR #14).

## Deployment status

**Backend deployed and tested as a rollback-only transaction.**
- Remote project `uebzvfzpbqqttbqyxxos` migration version `20261116061531`,
  name `db01_owner_initial_setup_rpc_audit_20261116`.
- GitHub migration mirror:
  `supabase/migrations/20261116061531_db01_owner_initial_setup_rpc_audit_20261116.sql`.
- Existing verified Owner and first campus unchanged.
- The live `initial_setup.status` is still **pending**. No real currency,
  timezone, campus name or academic year was inferred or saved.

## User flow

1. Owner signs in with their existing Supabase Auth email and password.
2. Flutter verifies identity, active profile, exact active school-wide Owner
   membership, active school and authorized campus via DB01 RLS.
3. If setup is incomplete, the app automatically opens **Owner Control Panel**.
4. Owner enters actual school name, first campus name, currency, IANA timezone,
   academic-year name, starts-on and ends-on dates.
5. Save invokes `public.owner_complete_initial_setup` with authorized school
   UUID, campus UUID and expected school/campus revision numbers.
6. A public SECURITY INVOKER wrapper calls a **private SECURITY DEFINER**
   function in `app_private`. Private function verifies auth.uid(), active
   confirmed nonanonymous Auth user, active profile and Owner role.
7. PostgreSQL locks school/campus/settings, validates all input, rejects stale
   revisions, updates school/campus, inserts active academic year, marks setup
   complete and appends an immutable-to-client audit event **in one transaction**.
8. Flutter reloads verified school/campus/year state and shows completed setup.
   No client direct UPDATE grants on school/campus/year/setting/audit tables.
9. Initial setup cannot be repeated. Later edits/year rollover need separate
   audited Owner operations in future work.

## Validation and security
- School and campus names 2–200 characters.
- Currency: three uppercase letters, **XXX forbidden**. Curated dropdown
  plus custom three-letter option; this is format validation and does not
  verify membership of every ISO-4217 code in a full registry.
- Timezone: validated by PostgreSQL's `pg_timezone_names` IANA catalog.
- Year name 4–30 characters, date end later than start and no more than
  550 days after start.
- Active school, active campus linked to school, first setup pending and
  no pre-existing academic-year rows required.
- Expected revision numbers prevent silent overwrite from stale clients.
- Only `authenticated` has EXECUTE on the public RPC; `anon` does not.
- Audit events have RLS, read-only to authorized Owner, and no direct
  authenticated write grants.
- SQL testing confirmed denial for unknown user, invalid currency/timezone,
  stale revision, atomic success, audit creation and duplicate-finalization
  rejection; all sample changes were rolled back.
- No production user password was accessed, transmitted or changed.

## Flutter source
- `lib/features/owner/presentation/owner_initial_setup_form.dart`
- `lib/features/owner/presentation/owner_control_panel_page.dart`
- `lib/features/auth/data/owner_auth_gateway.dart`
- `lib/main.dart`
- Widget test sources:
  `test/features/owner/owner_initial_setup_form_widget_test.dart`,
  `test/features/owner/owner_control_panel_widget_test.dart`,
  `test/features/auth/owner_auth_widget_test.dart`
- SQL replay/integration source:
  `supabase/tests/DB01_OWNER_SETUP_INTEGRATION.sql`.

## Windows test on the laptop

```powershell
git fetch origin
git switch auth/first-owner-bootstrap-20261116
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test

flutter run -d windows `
 --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co `
 --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PROJECT_KEY
```

Sign in with the existing Owner account and its password. Only the
publishable key goes in Flutter. Never put a `service_role` or `sb_secret_`
key in the client or repository. Test dark and light themes and Android
screen layout. Click Save **only with actual school values**.

**Not yet independently verified:** Flutter compilation/analyzer/widget
runtime (Flutter SDK unavailable in assistant environment); real end-to-end
Owner password sign-in on device. Auth sessions are intentionally not
persisted in plaintext until encrypted per-device storage is implemented.

**Still unavailable:** Real finance, fee collection, attendance, admission
submission, payroll, backup, sync and dashboard statistics. Completing school
setup does not activate unimplemented domains.

Supabase security advisor currently reports leaked-password protection
disabled (project plan/setting dependent). See:
https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
