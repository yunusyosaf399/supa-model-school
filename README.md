# Supa Model School Management System

Private development repository for the Supa Model School Windows and Android Flutter app and its Supabase backend.

**Status:** Architecture and schema authoring in progress. **Not production ready.** No school-domain database schema has been deployed.

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

**Do not skip `build_runner`.** The Drift source contains
`part 'campus_cache_database.g.dart';` and its generated Dart file is not
checked in. Generate it before using `flutter analyze`, `flutter test` or
`flutter run`. The repository currently pins Drift and drift_dev to
`2.32.1`, a Dart 3.9-compatible version. `flutter pub get` will refresh
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
- Supabase SQL under `supabase/drafts/` is **review-only**; no live schema has
  been deployed or migrated. The Edge Function is not deployed.
- Drift offline database/outbox code is **not wired to the UI**. It needs
  verified campus/device authorization, encryption, generated code and runtime
  tests before storing any real student/guardian information.
- Flutter code generation, analyzer, widget tests, Windows/Android launch,
  PostgreSQL SQL execution and device sync are **not verified yet**.
- No GitHub Actions workflows were run or requested for these merges.

Start by running the commands above and share any failures; test results will
be recorded in `planning/STATUS.md` after verification.
