# Current development status

Date: 2026-11-15

## Verified
- [x] Supabase project `uebzvfzpbqqttbqyxxos` created in SUPA MODEL SCHOOL connection, ap-south-1; status ACTIVE_HEALTHY.
- [x] Private GitHub repository `yunusyosaf399/supa-model-school` exists, push permission confirmed.
- [x] README, Flutter starter shell, architecture/security/SRS/docs and CI definition committed to main.
- [x] [Draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1) contains DB01 and DB02 SQL draft files; not merged/deployed.
- [x] Three-week GitHub issues #2/#4/#5 and schema review issue #3 created.
- [x] Machine-readable 114-task tracker is committed.

## Current count
**18 complete, 93 pending, 1 in progress, 2 blocked (total 114).**

## Blockers
- SETUP-07 and D01-T05: Flutter/Windows/Android validation awaits the user's local computer. Automatic GitHub Actions workflow has been removed by request; former CI issue #6 closed as not planned (no passing build claimed).
- DB01/DB02 are draft SQL on [PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1); deployment, RLS tests and merging remain pending.

## Active schema draft work
- D02-T03 **DONE (authoring/static checks)**: DB01 foundation schema hardened on [draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1). Structural review verified **12 public tables / 12 RLS ENABLE statements**, with no write policies. See DB01_OWNER_BOOTSTRAP.md, DB01_RLS_MANUAL.md, and check_db01.py on PR branch. **D02-T04 is IN_PROGRESS: transactional SQL fixture, Windows runner, and evidence template are committed; actual PostgreSQL execution and two-campus RLS tests remain outstanding.**
- D03-T01 **DONE (authoring/static checks)**: DB02 student/guardian identity and relationships tightened; student/guardian structural constraints verified as part of the updated 10-table DB02 draft. Added `supabase/tests/check_db02.py` and `DB02_STUDENT_GUARDIAN_TEST_PLAN.md`. Actual PostgreSQL migration and runtime RLS verification remain pending.
- D03-T02 **DONE (authoring/static checks)**: DB02 conditional admissions and four document-related tables drafted, with 24 acceptance cases, storage security design and 10/10 RLS structural review. Still NOT migrated, runtime-tested or deployed. Trusted status transitions and Storage bucket/policies remain future implementation.
- D03-T03 **DONE (source implementation/static checks only)**: trusted admission transaction functions, parent guardian draft table, school-wide counter, operation-audit table, verified Supabase Auth Edge route and local acceptance SQL committed to [draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1). **No local PostgreSQL tests or Edge runtime compile/deploy** yet.
- D03-T04 **DONE (UI authoring/static review only)**: six-stage Flutter admission wizard preview with responsive desktop/Android layout, student/guardian/academic/documents/fees/review stages, UI validation, unit/widget test sources, and no false save/payment/verification claims. Draft [UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7) is UNMERGED; Flutter analyzer and widget tests NOT RUN.
- D03-T05 **DONE (UI authoring/static source checks only)**: Flutter campus-scoped student directory preview, synthetic Campus A data, search by name/registration, filters, mobile cards / desktop table, read-only profile and unit/widget tests in [draft UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7). **No live database, real authorization, persistence, Flutter build or widget-test result.**
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
