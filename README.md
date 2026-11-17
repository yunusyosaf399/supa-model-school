# Supa Model School Management System

Private development repository for the Supa Model School Windows and Android Flutter app and its Supabase backend.

**Status (2026-11-17):** DB01–DB09 schema deployed (169 RLS-enabled public tables). **Not production ready:** server operations, end-to-end role/security checks, desktop sync, and application integration remain unfinished.

- Online backend: Supabase project `uebzvfzpbqqttbqyxxos` (`ap-south-1`).
- Desktop: assigned-campus SQLite/Drift offline + authenticated two-way sync.
- Android: authorized online data entry.
- Languages: English first; Pakistani Urdu optional.
- Deadline: 21-day **pilot** plan, subject to testing and financial reconciliation gates.

## Start here
- `docs/01_SRS.md` — requirements and scope.
- `docs/02_ARCHITECTURE.md` — client/server and deployment boundaries.
- `docs/03_DATA_MODEL.md` — domain entities and integrity constraints.
- `docs/04_SYNC_PROTOCOL.md` — offline sync, conflicts, idempotency.
- `docs/05_PERMISSIONS.md` — campus roles and permissions.
- `supabase/drafts/` — review-only prototypes; deployed DB01–DB09 migration history is separate. DB10 RPC is a new review-only draft.
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

- Admission wizard and student directory show **fictional preview data only**,
  and submission/upload is disabled.
- Supabase SQL under `supabase/drafts/` is **review-only**; DB01–DB09 schemas
  have been deployed, but DB10 APIs and live operational integrations are not deployed.
- Drift offline database/outbox code is **not wired to the UI**. It needs
  verified campus/device authorization, encryption, generated code and runtime
  tests before storing any real student/guardian information.
- Flutter code generation, analyzer, widget tests, Windows/Android launch,
  end-to-end service authorization and device sync are **not verified yet**; schema-level PostgreSQL checks have run.
- No GitHub Actions workflows were run or requested for these merges.

Start by running the commands above and share any failures; test results will
be recorded in `planning/STATUS.md` after verification.
