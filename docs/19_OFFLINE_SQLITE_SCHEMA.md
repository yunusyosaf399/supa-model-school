# D04-T01 — Campus-bound offline Drift/SQLite v1

**Historical D04-T01 baseline:** initial 11-table schema authored. D04-T02 adds two durable operation tables, raising the current schema to version 2 (13 tables); see docs/20_OFFLINE_OUTBOX.md. SQLite/Flutter runtime tests remain pending.
Local SQLite/Drift code-generation, Dart compilation, encryption and real offline sync remain to be verified separately.

## Strict platform and campus scope
- **Only one designated Windows desktop per campus** may enable offline editing in the pilot. All Android clients and all other PCs are online-only.
- The opening API \`CampusCacheDatabase.forWindowsFile(File(...))\` rejects non-Windows production use. It does NOT open a database automatically and is not connected to the application UI.
- A trusted app service must verify current Auth session, registered device assignment, school/campus access and offline authorization expiration ONLINE **before calling** \`bindVerifiedAssignment\`.
- The SQL singleton binding pins one school, campus and device. Every scoped business row has a composite FK \`(school_id,campus_id)\` to the single binding row; child FKs also include school/campus to prevent mismatched parents.
- **SQLite is not authorization or encryption**. Database files, WAL/shm backups, PII, password/keys and revoked permissions must be protected by a separate reviewed encryption, OS storage and session strategy.
- No real child or guardian PII should be placed in this unencrypted schema until encryption and restore/authorization tests pass.

## Eleven local tables

| Table | Purpose |
| --- | --- |
| \`local_campus_binding\` | One registered desktop + school/campus |
| \`local_academic_years\` | Scoped read-only year reference |
| \`local_classes\` | Scoped classes with year FK |
| \`local_sections\` | Scoped section/class reference |
| \`local_students\` | Minimal campus student directory replica |
| \`local_guardians\` | Scoped guardian identity/contact (future protected data) |
| \`local_student_guardians\` | Scoped relationship with one-primary index |
| \`local_enrollments\` | Current and historical academic allocation |
| \`local_admissions\` | Admission draft/status/expected cloud revisions |
| \`local_admission_documents\` | Required document status/metadata only; NO file bytes |
| \`local_replica_metadata\` | Opaque cursor placeholder, advanced only by future atomic sync |

The schema stores dates as ISO YYYY-MM-DD **text** and event timestamps as UTC Unix milliseconds. No REAL/float money is stored. All cloud UUIDs are represented as strings. Student registration is unique per school (case-insensitive). Server-supplied academic years and classes are constrained to the local campus.

## What is NOT implemented by D04-T01
- No persistent outbox/operation IDs, no deferred-payment logic and no automatic synchronization: **D04-T02–T04**.
- No cloud change-feed, conflict resolution or tombstone handling.
- No actual Auth session/device enrollment, expiration, revocation or cryptographically verified assignment.
- No SQLCipher/encryption key management, no protected backup/restore system, no secure file upload/download cache.
- No local DAO exposed to the admission wizard or student directory: those screens remain UI previews.
- No database migration to SQLite schema v2; upgrades fail closed until explicitly reviewed.
- No Supabase schema deployed; the local SQLite schema is separate from PostgreSQL.

## Source layout
- \`lib/offline/schema/campus_cache.drift\`: authoritative v1 SQL schema used by Drift code generation.
- \`lib/offline/campus_cache_database.dart\`: Windows-only native SQLite connection, foreign_keys ON, background isolate, bind guard and migration version.
- \`test/offline/campus_cache_database_test.dart\`: Dart tests (require generated \`.g.dart\`).
- \`scripts/test_local_drift_schema_sqlite.py\`: actual-schema validation using Python's in-memory SQLite.
- \`pubspec.yaml\`: pinned compatible Drift/build dependencies; a lockfile must be generated and committed **on the laptop**.

## Laptop verification
1. Checkout \`db/d04-local-drift-schema\`.
2. Install Flutter and Windows desktop dependencies; \`flutter doctor -v\`.
3. Run \`flutter pub get\`, then \`dart run build_runner build --delete-conflicting-outputs\` to generate \`campus_cache_database.g.dart\`.
4. Run \`python scripts/test_local_drift_schema_sqlite.py\` to execute the actual SQL constraints against SQLite.
5. Run \`flutter analyze\` and \`flutter test test/offline/campus_cache_database_test.dart\`.
6. Run \`dart run drift_dev schema export lib/offline/campus_cache_database.dart\` and save the schema snapshot for future migrations.
7. Review Android access: production \`forWindowsFile\` must fail on Android.
8. Review sensitivity of guardian data and local cache/backup encryption before enabling real school records.

## Acceptance criteria
- [x] One binding row enforced, campus-scoped FK relationships defined (source review).
- [x] Academic/student/admission/document schema and uniqueness/indexes authored.
- [x] Windows-only Drift wrapper, schema version and pragma checks authored.
- [x] Python SQLite and Dart test suites authored.
- [ ] Python SQLite exact-schema suite executed successfully.
- [ ] Dart build_runner generated code and passed \`flutter analyze/test\`.
- [ ] Encrypted local store and device offline authorization verified.
- [ ] Actual offline student/admission sync tested on a designated Windows device.

This task's **source implementation** can be marked DONE. Runtime checks and secure offline operation are NOT complete.
