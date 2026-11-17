# DB08 Local-Only Approval Test Runbook

**Do NOT run on hosted school.** DB08 depends on DB01/DB02 baselines, plus DB03–DB07 stacked drafts. Create the user identities `sms-adm-admin-a@example.invalid` and `sms-adm-reviewer-b@example.invalid` in disposable local Supabase Auth.

```powershell
python supabase/tests/check_db08_schema.py
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB08_APPROVALS_INTEGRATION.sql
```

Neither command has been run by this task. Source checker proves strings/structure, not valid PostgreSQL; SQL fixture BEGIN/ROLLBACK protects fictional data only, still use isolated database.

**Before acceptance, verify:** (1) school Owner roles and correctly campus-scoped all-other roles; (2) active grants/overrides and removed permissions invalidate access immediately, not after JWT refresh; (3) principal finance summary permission and accountant/payroll privacy; (4) two-campuses cannot reference each other's approvals; (5) requester cannot review own expense even through delegation; (6) two simultaneous reviewers can't both commit the same step; (7) versioned policy and minimum threshold applied by trusted server; (8) approvals/returns/rejections create immutable audit and cannot replay twice; (9) inventory, tuition, payroll and admission business mutations commit atomically after approval; (10) offline pending requests NEVER finalize without online authorized decision; (11) role additions never grant data access through RLS by themselves; (12) document templates do not execute arbitrary SQL/HTML and never expose student PII; (13) no direct authenticated client writes to role/approval/audit tables.

**Known blockers:** SQL defines stage rows but not trusted stage-transition engine or RLS read policies; workflow subject registry requires online entity checks; DB09 needs device-level offline expiration/revocation; all source FKs/revisions must be executed and tested locally. No deployment or Flutter changes.

After DB08, **1 full domain design remains (DB09), 7 domains remain undeployed**.
