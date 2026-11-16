# Current development status

Date: 2026-11-16

## Verified
- [x] Supabase project `uebzvfzpbqqttbqyxxos` created in SUPA MODEL SCHOOL connection, ap-south-1; status ACTIVE_HEALTHY.
- [x] Private GitHub repository `yunusyosaf399/supa-model-school` exists, push permission confirmed.
- [x] README, Flutter Android/Windows project, UI preview source, schema drafts, test runbooks and task documentation committed; no GitHub Actions in use.
- [x] [PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1) DB01/DB02 SQL draft source merged to main; **not deployed/executed**.
- [x] Three-week GitHub issues #2/#4/#5 and schema review issue #3 created.
- [x] Machine-readable 114-task tracker is committed.

## Current count
**25 complete, 88 pending, 1 in progress, 0 blocked (total 114).**

## Remaining verification gates
- User reported a successful Windows Flutter build and passing tests on 2026-11-15, after the admission wizard constructor fix. Logs not supplied for independent verification. Android build and explicit Flutter analyzer evidence remain pending; D02-T02 remains TODO.
- No GitHub Actions are running. DB01/DB02 source is merged to main, but PostgreSQL migration, two-campus RLS tests, trusted offline device authorization, encryption and deployment remain pending.

## Active schema draft work
- D02-T03 **DONE (authoring/static checks)**: DB01 foundation schema hardened on [draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1). Structural review verified **12 public tables / 12 RLS ENABLE statements**, with no write policies. See DB01_OWNER_BOOTSTRAP.md, DB01_RLS_MANUAL.md, and check_db01.py on PR branch. **D02-T04 is IN_PROGRESS: transactional SQL fixture, Windows runner, and evidence template are committed; actual PostgreSQL execution and two-campus RLS tests remain outstanding.**
- D03-T01 **DONE (authoring/static checks)**: DB02 student/guardian identity and relationships tightened; student/guardian structural constraints verified as part of the updated 10-table DB02 draft. Added `supabase/tests/check_db02.py` and `DB02_STUDENT_GUARDIAN_TEST_PLAN.md`. Actual PostgreSQL migration and runtime RLS verification remain pending.
- D03-T02 **DONE (authoring/static checks)**: DB02 conditional admissions and four document-related tables drafted, with 24 acceptance cases, storage security design and 10/10 RLS structural review. Still NOT migrated, runtime-tested or deployed. Trusted status transitions and Storage bucket/policies remain future implementation.
- D03-T03 **DONE (source implementation/static checks only)**: trusted admission transaction functions, parent guardian draft table, school-wide counter, operation-audit table, verified Supabase Auth Edge route and local acceptance SQL committed to [draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1). **No local PostgreSQL tests or Edge runtime compile/deploy** yet.
- D03-T04 **DONE (UI authoring/static review only)**: six-stage Flutter admission wizard preview with responsive desktop/Android layout, student/guardian/academic/documents/fees/review stages, UI validation, unit/widget test sources, and no false save/payment/verification claims. Draft [UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7) is UNMERGED; Flutter analyzer and widget tests NOT RUN.
- D03-T05 **DONE (UI authoring/static source checks only)**: Flutter campus-scoped student directory preview, synthetic Campus A data, search by name/registration, filters, mobile cards / desktop table, read-only profile and unit/widget tests in [draft UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7). **No live database, real authorization, persistence, Flutter build or widget-test result.**
- D04-T01 **DONE (Drift schema source only)**: [Draft PR #8](https://github.com/yunusyosaf399/supa-model-school/pull/8) defines 11 local SQLite tables with one-device/one-campus binding and scoped FKs, Windows-only Drift native connection, schema migration gate, SQL/Dart test sources and [implementation runbook](https://github.com/yunusyosaf399/supa-model-school/blob/db/d04-local-drift-schema/docs/19_OFFLINE_SQLITE_SCHEMA.md). **Exact SQLite script, Drift generator, Flutter compiler/tests have not been executed.** No offline authorization/encryption or actual sync/outbox implemented.
- D04-T02 **DONE (outbox source design/implementation only)**: [Draft PR #8](https://github.com/yunusyosaf399/supa-model-school/pull/8) now includes a **13-table Drift v2** local schema, two durable outbox/audit tables, three indexes and four immutability triggers, non-destructive v1→v2 migration source, UUIDv4 idempotency, atomic draft+queue, ordered leasing/retry/conflict/ack, WAL synchronous FULL, Python SQLite/Dart test sources and [outbox runbook](https://github.com/yunusyosaf399/supa-model-school/blob/db/d04-local-drift-schema/docs/20_OFFLINE_OUTBOX.md). **Actual SQLite/Flutter/migration testing and encryption are still pending.**
- Supabase cloud project remains empty of school-domain public tables. No migration has been deployed.

## Next approved work
1. D02-T04: On a local PostgreSQL/Supabase stack, generate CLI DB01 migration, bootstrap fictional Auth users, run supabase/tests/DB01_RLS_INTEGRATION.sql via scripts/test_db01_local.ps1, and record evidence. The schema and tests are in draft PR #1. Review DB02 separately.
2. Configure school-specific values and seed fictional two-campus test users.
3. Prove RLS denial, owner bootstrap and cross-campus access constraints.
4. Build student admission and offline sync vertical slice.
5. Deploy only reviewed, tested migrations and confirm live tables.

**Not done:** production school tables, RLS test proof, storage policies, real login, offline sync, financial operations, approved school release.

## Supabase
[Project dashboard](https://supabase.com/dashboard/project/uebzvfzpbqqttbqyxxos). Project active, school-domain schema not deployed.

## Session 2026-11-15 — Verification blocker
- DB01 draft tightened: principal detailed-report grants require active principal role and membership; campus settings are Owner-only; one active offline device per campus.
- Added transactional two-campus plus other-school RLS integration SQL, local PowerShell runner, and test evidence template to draft PR #1.
- Static source checks can be reviewed; **local PostgreSQL server and Supabase CLI are unavailable in assistant environment**. D02-T04 remains IN_PROGRESS, not DONE.
- No school-domain migration deployed to the connected Supabase project.

## Session 2026-11-15 — D03-T01 completed (design only)
- Prevented duplicate school registration IDs differing only by case.
- Added school-scoped composite foreign keys, one-primary-guardian and one-parent-relationship uniqueness; sibling guardian reuse stays permitted.
- All seven DB02 public tables carry RLS ENABLE; no client CRUD grant/policy added. Checked source structurally.
- No SQL was run against Supabase; no migration has been deployed. D02-T04 still requires local PostgreSQL verification.

## Session 2026-11-15 — D03-T02 completed (schema authoring only)
- Draft PR #1 now includes conditional admissions and document deadlines, upload versions, review audit, deadline-change history.
- Static source review: **10 public DB02 tables / 10 RLS ENABLE statements**, with no direct document access grants.
- Test catalog: `supabase/tests/DB02_DOCUMENT_ACCEPTANCE.md` has 24 scenarios. Storage plan: `supabase/drafts/DB02_DOCUMENT_STORAGE_PLAN.md`.
- D03-T03 (implement trusted admission workflow) is the next coding task. PostgreSQL migration tests, Storage policies, and authorized RPCs remain unimplemented.
- User will run local tests later; no CI workflows run and no schema deployed to cloud.

## Session 2026-11-15 — D03-T03 source implementation completed
- Added `supabase/drafts/DB02_WORKFLOW_SCHEMA.sql` (3 public tables with RLS, campus/guardian and operation constraints).
- Added `supabase/drafts/DB02_ADMISSION_OPERATIONS.sql` (6 non-exposed SECURITY DEFINER functions: authorization, approval setting, finalization, save, submit and review).
- Added `supabase/functions/admissions/index.ts` (verified Auth token, server-only Postgres connection, parameterized SQL; no service-role key in Flutter).
- Added `supabase/tests/ADMISSION_WORKFLOW_INTEGRATION.sql`, 40 acceptance scenarios and a static checker.
- Local SQL/Edge runtime, multiple-campus isolation, enrollment rollback and concurrent retries are NOT TESTED. Do NOT merge/deploy to production until tests pass.
- D02-T04 remains IN_PROGRESS, D07-T01 remains TODO, and D05-T03 numbering runtime verification remains TODO.

## Session 2026-11-15 — D03-T04 authored (local UI, not compiled)
- Branch `ui/d03-admission-wizard`, draft PR #7 includes model, responsive screen and wired Students preview entry.
- No real campus/class identifiers are used; options are explicitly fictional. No Auth call, Storage upload, fee ledger posting, save draft or submit action.
- Tests authored: `test/features/admissions/admission_draft_test.dart` and `admission_wizard_widget_test.dart`; static reviewer source checks authored and inspected.
- Remaining: compile/analyze/widget tests on Windows Flutter laptop, layout/overflow verification, real backend integration under later task D05-T01.
- No GitHub Actions workflows requested or run.

## Session 2026-11-15 — D03-T05 authoring completed
- UI branch `ui/d03-admission-wizard`, draft PR #7 now includes `lib/features/students/models/student_directory.dart` and `lib/features/students/presentation/student_directory_page.dart`.
- Search, status/class and authorized-campus UI filters, count/empty state, desktop table, mobile cards and read-only fictional profile authored; Students tab now opens directory and admission wizard.
- Tests authored: `test/features/students/student_directory_model_test.dart`, `student_directory_widget_test.dart`; docs and static guardrail checker committed.
- **Access security:** current in-memory projection is NOT authorization. Before real data, backend RLS and assigned-campus SQLite containment must enforce access and server-side search/pagination.
- **Local runtime verification pending:** Flutter SDK unavailable in this environment; no GitHub Actions requested or run. No Supabase migrations deployed.

## Session 2026-11-15 — D04-T01 offline schema authored (not runtime-verified)
- Branch `db/d04-local-drift-schema`; draft PR #8 is separate from DB01/DB02 PR #1 and Flutter UI PR #7.
- Added `lib/offline/schema/campus_cache.drift`: 11 local tables, singleton pinned school+campus, scoped composite FKs, unique indices for student registration and active enrollments; no money floats.
- Added `lib/offline/campus_cache_database.dart` using Windows-only NativeDatabase background isolate, foreign key PRAGMA and fail-closed upgrade/mismatched device binding behavior.
- Pinned `drift` and `drift_dev` 2.35.3 and `build_runner` 2.15.1; `pubspec.lock` and generated `.g.dart` will be generated after local toolchain tests.
- Added exact-schema Python SQLite test `scripts/test_local_drift_schema_sqlite.py` and Dart in-memory tests; files committed but **not executed**.
- D04-T02 durable sync outbox, D04-T03 idempotent ingest, D04-T04 change cursor, D04-T05 offline vertical slice remain TODO. Local encryption/authorization still required before real data.
- No GitHub Actions jobs run, no hosted Supabase SQL changes made.

## Session 2026-11-15 — D04-T02 outbox source authored
- Branch `db/d04-local-drift-schema`, draft PR #8: local schema version 2 with `local_outbox_operations` and `local_outbox_events`; 13 tables total. Added append-only events, immutable original operation envelopes and no-delete policy via SQL triggers.
- Added `lib/offline/offline_outbox_repository.dart` with UUIDv4 generation, atomic local admission + queue transaction, duplicate operation-ID replay protection, oldest-first dispatch, time-limited lease/reclaim and stale token fencing, retry backoff, conflict hold and verified-server-only ack API.
- Updated Drift v1→v2 migration source to add tables/indexes/triggers; WAL synchronous FULL protects committed local data. No destructive table migration authored.
- Updated exact-schema SQLite test runner and Dart unit tests for operation persistence and file close/reopen. All source files/readbacks structurally checked, **not executed**.
- **Not ready for real PII**: offline session expiry/revocation, encryption/key management, consistent backups, authenticated server ingest and cloud ID/revision mapping are unfinished.
- D04-T03 (server idempotent ingest) next; D04-T04 (cloud cursor), D04-T05 (integration) remain TODO. No GitHub Actions runs or Supabase hosted DDL deployment.

## Session 2026-11-15 — repository integration audit and main-branch merges
- **Merged** Android Studio project runners [PR #9](https://github.com/yunusyosaf399/supa-model-school/pull/9), Flutter preview UI [PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7), Supabase UNDEPLOYED drafts [PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1), offline Drift source [PR #8](https://github.com/yunusyosaf399/supa-model-school/pull/8).
- Fixed SDK mismatch: Android Studio uses Dart **3.9.2**; merged offline pubspec now requires >=3.9.0 with Drift/drift_dev **2.32.1**, verified as Dart 3.9-compatible via pub.dev. Removed duplicate unused Android MainActivity for com.suffah.sms; Gradle uses com.example.sms.
- D02-T01 **DONE for Android/Windows runner source creation**, NOT for a passing build. Added README first-run guidance.
- IMPORTANT BEFORE TESTING: run `flutter pub get`, then `dart run build_runner build --delete-conflicting-outputs`, then `flutter analyze` and `flutter test`. Drift-generated `campus_cache_database.g.dart` is deliberately not checked in; the previous `pubspec.lock` was generated before Drift dependencies and must be regenerated/committed after successful local resolution.
- Structural GitHub branch/readback checks completed. **Cannot claim compiled Flutter, complete SQLite/Drift execution or PostgreSQL RLS test success** from this environment. Resolve failures from local command output before any production approval.
- No GitHub Actions were run, no hosted Supabase schema applied, no database live data created.

## Session 2026-11-15 — D04-T03 offline ingestion authored
- **Source completed:** [draft PR #12](https://github.com/yunusyosaf399/supa-model-school/pull/12) adds `supabase/drafts/DB04_OFFLINE_INGEST.sql` with 3 private RLS-enabled tables, an immutable operation receipt and a trusted private transaction, plus `supabase/functions/offline-ingest/index.ts`, static checker, SQL fixture and runbook.
- Backend reuses DB01's `registered_devices` table. Current actor/campus/device assignment and secret proof are validated; exact UUID replay returns stored receipt, modified payload fails, new local versions map to the same cloud application with optimistic locking.
- **Structural source inspection passed**, but SQL execution, concurrency, device-proof provisioning, Edge runtime and PostgreSQL integration have **not run**. No hosted Supabase schema/tables or function deployment. No GitHub Actions.
- **Windows test reported by user:** Flutter tests passed and app built successfully after constructor fix. This is the user's report (not verified build logs). D02-T02 Flutter analyzer evidence and Android run remain unverified; SETUP-07 and D01-T05 updated to DONE (user-reported Windows).
- **Correction of earlier dependency guidance:** Drift 2.32.1 is NOT compatible with the user's Dart 3.9.2 dependency resolution. [PR #10](https://github.com/yunusyosaf399/supa-model-school/pull/10) corrected to Drift 2.31.0 + sqlite3 2.x; user subsequently reported build/test success.
- Next **D04-T04 cloud change log + cursor**, D04-T05 full offline sync integration after RLS/credential/encryption gates. D02-T04 local PostgreSQL two-campus RLS integration remains IN_PROGRESS.

## Session 2026-11-16 — D04-T04 server change log and cursor source authored
- **Source complete:** [stacked draft PR #13](https://github.com/yunusyosaf399/supa-model-school/pull/13) branches from [draft PR #12](https://github.com/yunusyosaf399/supa-model-school/pull/12), not main; change-feed SQL must never be deployed without prior D04 ingest/device credentials.
- Added `supabase/drafts/DB04_CHANGE_FEED.sql`: private append-only RLS-protected admission event log with campus index, INSERT/UPDATE/DELETE triggers, TRUNCATE guard, latest-state backfill and global transaction-scoped advisory lock before identity-number allocation to avoid out-of-commit-order cursor skips.
- Added `supabase/functions/offline-pull/index.ts`: verified Auth user, current campus/registered Windows device credential, bounded 1–100 page size, decimal-string `after_cursor`, lossless `change_seq`/`next_cursor`, has_more and deletion tombstone.
- Added rollback-only SQL fixture `supabase/tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql`, static checker, Edge API README, separate-session concurrency runbook and Supabase docs index.
- **Structural GitHub source readback: 19/19 targeted assertions passed.** PostgreSQL migration/RLS tests, concurrency fixture, Deno Edge invocation, device security, local SQLite event application and cursor atomically persisted have **not been executed or implemented**. User-reported Windows Flutter UI build success does NOT validate server sync.
- No hosted Supabase DDL changes/deployments, no GitHub Actions. Live public school tables remain uncreated pending separate verification.
- **Next D04-T05:** authorized Windows offline vertical slice: secure device credentials, encrypted persistence, dispatch/ingest receipt, local cloud UUID mapping, event apply + cursor in one local transaction, restart/conflict and device tests. D02-T04 local PostgreSQL RLS still IN_PROGRESS.

## Session 2026-11-16 — First Owner Auth preparation (PR #15; source only)
- **Not yet activated:** hosted Supabase Auth had 0 users and the DB01 foundation had 0 tables/0 migrations when checked. No Owner invitation, password, profile, role, school or campus has been created on the hosted project.
- Added Owner Auth gateway and integrated email/password sign-in into Flutter. Login is allowed only after server-verified Auth identity, active profile, one school-wide Owner membership, active school and authorized campus membership are confirmed. Invalid session is signed out.
- The configured login selects campus AFTER authentication and keeps the existing debug preview separate; real dashboard statistics remain fictional placeholders.
- Supabase client uses the publishable key only, and `EmptyLocalStorage` disables persistence of Auth session tokens until encrypted storage is built/tested.
- Added one-time privileged Owner bootstrap SQL template, verified-email requirement, detailed runbook and fake-gateway Flutter widget tests.
- Static source checks only. Flutter analyzer, SDK dependency lock resolution, widget tests, DB01 RLS migration tests and actual auth/campus integration remain **NOT RUN**.
- **Activation gate:** Owner email identity not yet explicitly specified; user must accept a trusted Supabase Auth invitation. DB01 migration/RLS tests, school currency/timezone, and first campus require explicit configuration. Do not use guessed credentials or manually insert auth.users.

## Session 2026-11-16 — First Owner activation completed (live DB01)
- **ACTIVATED:** The verified existing Supabase Auth user for the school was promoted to one active, school-wide `owner` role. No password was accessed or modified.
- **MIGRATED:** Applied remote DB01 version `20261116051446` (`db01_foundation_owner_access_20261116`); 12 public tables, all with RLS enabled, confirmed against hosted database. Exact version mirrored under `supabase/migrations/`.
- **TESTED IN POSTGRES:** Transactional create/rollback test for two in-school campuses and foreign school; Owner RLS read allowed both owned campuses and denied the foreign school. After seeding, privileged verification and Owner/unknown-JWT RLS checks passed. The original 7-user fixture remains unexecuted and is still required.
- **INITIAL SETUP PENDING:** School `Supa Model School`, first campus `Main Campus (Setup Pending)`, currency `XXX` and timezone `Etc/UTC` as explicitly non-final placeholders; academic year not yet seeded. The `initial_setup` setting records pending status. No real finance, students or attendance data created.
- **AUTH UI SOURCE:** PR #15 contains authenticated Owner login, authorized campus choice, signout, Owner Control Panel read-only setup summary and a Supabase Auth current-password-verified change-password screen.
- **SECURITY ADVISOR:** Auth leaked-password protection disabled warning; Supabase advisor URL documented in docs/23.
- **UNVERIFIED:** Flutter widget tests/analyzer/runtime (SDK not available), real password login by user, encrypted session storage, full seven-user RLS suite, auth recovery URLs, setup edit service and actual operational modules. No workflows triggered.

## Session 2026-11-16 — Owner initial school setup backend and Flutter (stacked PR #15)
- **DEPLOYED SQL:** remote Supabase migration `20261116061531_db01_owner_initial_setup_rpc_audit_20261116`; exact source mirrored in `supabase/migrations/`.
- **DATABASE:** new RLS-enabled `public.owner_setup_audit_events` and secure `public.owner_complete_initial_setup` SECURITY INVOKER RPC backed by `app_private.complete_owner_initial_setup` SECURITY DEFINER. No unauthenticated execution or authenticated direct school/campus/year/audit writes.
- **SQL TESTS PASSED:** transactional rollback-only (not actual school values): invalid/unknown user rejected, placeholder currency/unknown IANA timezone/stale revision rejected, Owner's atomic school+campus+year+settings+audit operation succeeded, duplicate setup blocked. Original real data still unchanged.
- **LIVE STATUS:** school initial setup PENDING, currency XXX, timezone Etc/UTC, first campus still setup-pending, no academic year, zero setup audit records. Real values must be entered by Owner; no guessed calendar dates.
- **FLUTTER SOURCE:** Owner signs in, is taken automatically to Owner Control Panel while setup pending, and can enter real school/campus name, currency, timezone, academic-year label and dates, then Save Setup. After Supabase RPC confirms success, refresh authorized school/year context and show completion; account/password controls remain.
- **UNVERIFIED:** Flutter compilation/test commands and real Owner password session on Windows/Android. No Flutter SDK installed in assistant environment. Add credential storage hardening and full seven-account RLS harness before live school operations.
- **DISABLED/UNIMPLEMENTED:** Fees, attendance, admission writes, finance, backups, sync and dashboards remain previews. School setup completion does not turn these on.

## Session 2026-11-16 — Academic Structure (classes and sections) for Owner
- **DEPLOYED:** Supabase migration version `20261116081604_db01_owner_academic_structure_20261116`. Adds case-insensitive class/section uniqueness, RLS Owner-read-only academic audit table, and Owner-only atomic class+sections creation RPC in `app_private` with a public SECURITY INVOKER wrapper.
- **TESTED LIVE WITH ROLLBACK:** The SQL test source `supabase/tests/DB01_ACADEMIC_STRUCTURE_RLS_INTEGRATION.sql` passed on the hosted DB. Tests included Owner denied before initial setup completion, unknown user denied, duplicate casefold section rejected, Owner successful atomic create/audit, duplicate class rejected; the transaction ROLLBACK left zero permanent fixtures.
- **LIVE SCHOOL STATE UNCHANGED:** `initial_setup.status=pending`, no academic years/classes/sections/audits. Must not invent school year, campus roster or fees.
- **FLUTTER SOURCE COMMITTED:** `AcademicStructurePage` with real campus/active year selection, class & section creation, listing and refresh; `AcademicStructureRepository` with scope-filtered RLS reads and RPC writes; authorized Owner gateway now returns `activeYearId`. Shortcut under Owner Control Panel and a new `Academic Setup` navigation destination. Light/dark themes inherited from app.
- **STILL UNVERIFIED:** Flutter compilation, Windows/Android app runtime and widget test execution pending local SDK access; no actual authenticated password session tested by developer. PRs #14/#15 and next PR remain draft.
- **NEXT:** DB02 Admissions real data selection and approved admission flow after school setup and academic masters have actual data. The DB02 SQL is currently only a review draft; no student/fees operations were deployed.
