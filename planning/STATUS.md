# Current development status

Date: 2026-11-14

## Verified
- [x] Supabase project `uebzvfzpbqqttbqyxxos` created in SUPA MODEL SCHOOL connection, ap-south-1; status ACTIVE_HEALTHY.
- [x] Private GitHub repository `yunusyosaf399/supa-model-school` exists, push permission confirmed.
- [x] README, Flutter starter shell, architecture/security/SRS/docs and CI definition committed to main.
- [x] [Draft PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1) contains DB01 and DB02 SQL draft files; not merged/deployed.
- [x] Three-week GitHub issues #2/#4/#5 and schema review issue #3 created.
- [x] Machine-readable 114-task tracker is committed.

## Current count
**12 complete, 97 pending, 3 in progress, 2 blocked (total 114).**

## Blockers
- SETUP-07 and D01-T05: Flutter SDK not available locally. The GitHub Actions scaffold check [run #3](https://github.com/yunusyosaf399/supa-model-school/actions/runs/43621320297) also **failed**; logs/step details are presently unavailable through the connector. See [issue #6](https://github.com/yunusyosaf399/supa-model-school/issues/6). Do not claim a compiled/tested application.
- DB01/DB02 are draft SQL on [PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1); deployment, RLS tests and merging remain pending.

## Active schema draft work
- D02-T03: DB01 SQL drafted on [PR #1](https://github.com/yunusyosaf399/supa-model-school/pull/1); migration generation and RLS verification remain.
- D03-T01 and D03-T02: DB02 student/guardian and admissions document SQL drafted on PR #1; migration and permission tests remain.
- Draft files have deliberately not been deployed to Supabase.

## Next approved work
1. Review DB01/DB02 SQL draft PR #1; generate CLI migrations and run local tests.
2. Configure school-specific values and seed fictional two-campus test users.
3. Prove RLS denial, owner bootstrap and cross-campus access constraints.
4. Build student admission and offline sync vertical slice.
5. Deploy only reviewed, tested migrations and confirm live tables.

**Not done:** production school tables, RLS test proof, storage policies, real login, offline sync, financial operations, approved school release.

## Supabase
[Project dashboard](https://supabase.com/dashboard/project/uebzvfzpbqqttbqyxxos). Project active, school-domain schema not deployed.
