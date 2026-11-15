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
**13 complete, 96 pending, 3 in progress, 2 blocked (total 114).**

## Blockers
- SETUP-07 and D01-T05: Flutter/Windows/Android validation awaits the user's local computer. Automatic GitHub Actions workflow has been removed by request; former CI issue #6 closed as not planned (no passing build claimed).
- DB01/DB02 are draft SQL on [PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1); deployment, RLS tests and merging remain pending.

## Active schema draft work
- D02-T03 **DONE (authoring/static checks)**: DB01 foundation schema hardened on [draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1). Structural review verified **12 public tables / 12 RLS ENABLE statements**, with no write policies. See DB01_OWNER_BOOTSTRAP.md, DB01_RLS_MANUAL.md, and check_db01.py on PR branch. **D02-T04 is IN_PROGRESS: transactional SQL fixture, Windows runner, and evidence template are committed; actual PostgreSQL execution and two-campus RLS tests remain outstanding.**
- D03-T01 / D03-T02 **IN_PROGRESS**: DB02 student, guardian and conditional admission schema remains in draft; no runtime check.
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
