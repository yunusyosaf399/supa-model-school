# Supa Model School Management System

Private development repository for the Supa Model School Windows and Android Flutter app and its Supabase backend.

**Status:** DB01–DB10 school-domain backend and test fixtures deployed to Supabase. Flutter is under active development; **not production ready**.

- Online backend: Supabase project `uebzvfzpbqqttbqyxxos` (`ap-south-1`).
- Desktop: assigned-campus SQLite/Drift offline + authenticated two-way sync.
- Android: authorized online data entry.
- Languages: English first; Pakistani Urdu optional.
- Deadline: 21-day **pilot** plan, subject to testing and financial reconciliation gates.

## Start here
- `docs/01_SRS.md` — requirements and scope.
- `docs/51_HANDWRITTEN_FEATURE_EXPANSION_20261118.md` — 57 new/expanded requirements from the three notebook images, mapped to current modules and delivery gates.
- `planning/HANDWRITTEN_FEATURE_MATRIX_20261118.csv` — traceable per-item implementation status and next action.
- `supabase/seed/20261118_handwritten_financial_categories.sql` — optional category templates only; not deployed, does not post money.
- `docs/02_ARCHITECTURE.md` — client/server and deployment boundaries.
- `docs/03_DATA_MODEL.md` — domain entities and integrity constraints.
- `docs/04_SYNC_PROTOCOL.md` — offline sync, conflicts, idempotency.
- `docs/05_PERMISSIONS.md` — campus roles and permissions.
- `supabase/drafts/` — **review-only** SQL drafts; not deployed.
- `planning/STATUS.md` — verified work state, blockers and next tasks.

**Security:** Never commit database passwords, service-role keys or secrets. Do not enter real student/financial data until RLS, offline sync, transaction safety and restore tests pass.

## Android Studio / Windows first-run testing (Dart 3.9)

The Flutter Android and Windows platform projects and source drafts have been merged into `main`.
Keep the Android Studio **folder** named `sms` if preferred; the GitHub repo is
`supa-model-school` and the Dart package name is `supa_model_school`.

On your **Windows laptop**, open the repository folder (not the old `sms` backup)
in Android Studio, then run from the Flutter project root:

```powershell
flutter --version
flutter doctor -v
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter devices
flutter run -d windows
```

**Live UI login on a local debug build (17 Nov 2026):** A normal debug
`flutter run -d windows` or Android Studio Debug launch connects to the
configured Supa Model School test project automatically using a **public
publishable key**. No Supabase secret, service-role key or password is stored
in the repository. Sign in using your existing verified school **Owner**
email/password. The School/Campus field on the login page is informational:
the authorized school and campuses are loaded after sign-in.

The connected test database currently contains 32 students, five admissions
and a configured academic year. Use the authenticated Students and Admissions
modules to verify real Supabase reads; **Preview Dashboard** does not sign in
and will not display your real test data.

For a different project or a release build, supply explicit overrides:

```powershell
flutter run -d windows `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

If login fails, check that the user is confirmed in Supabase Auth and has
an active `owner` role, active profile and active school. The local
debug connection does not bypass your password or database permissions.
For a release/profile build, debug defaults are intentionally absent.


**Do not skip `build_runner`.** The Drift source contains
`part 'campus_cache_database.g.dart';` and its generated Dart file is not
checked in. Generate it before using `flutter analyze`, `flutter test` or
`flutter run`. The repository pins Drift and drift_dev to `2.31.0`, with `sqlite3` `2.9.4` and
`sqlite3_flutter_libs` `0.5.42` for Dart **3.9.2**. Drift 2.32.x migrated to
SQLite bindings 3.x, which do not resolve with that Dart SDK. This compatibility
set has been checked against published package requirements, but **dependency
resolution and native compilation must still be confirmed locally**. `flutter pub get` will refresh
`pubspec.lock` from the added Drift dependencies; review the changes and
commit the resolved lockfile once verified.

To check Android instead of Windows:

```powershell
flutter devices
flutter run -d <android-device-id>
```

The first Windows desktop build requires Visual Studio with the Desktop
development with C++ workload; Android requires a valid Android SDK and a
connected device or running emulator. Follow `flutter doctor -v` findings.

### Safety and maturity

- The database uses RLS and authenticated Owner/campus-scoped APIs.
  The live test database contains fictional student and admissions data.
- Admissions draft save, resume and certificate uploads are implemented,
  but Principal routing and real-device end-to-end tests are not complete.
- Offline Drift/outbox synchronization is not yet connected for production use.
- Run `flutter analyze --no-fatal-infos --no-fatal-warnings` and the
  focused widget regressions before treating local changes as validated.
- Do not include a service-role/secret key in Flutter or commit passwords.
