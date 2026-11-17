# All Core Schema Designs Authored — Migration and Integration Gates

**Current verified 2026-11-17 — ALL DB01–DB09 SQL SCHEMAS DEPLOYED; NOT a production-readiness certificate.**
DB03–DB09 were successfully tested via isolated GitHub Actions and applied as seven tracked migrations to the connected Supa Model School project. [PR #34](https://github.com/yunusyosaf399/supa-model-school/pull/34) merged the exact migration files to main. 169 public tables, all RLS-enabled; original school/campus/role preserved. **Remaining items below are security, service/API, accounting, real synchronization and operational-test gates—not yet-to-deploy schema DDL.** No Flutter changes in this workstream.

## Correct stacked source review order

1. DB03 Fees/Billing — [PR #25](https://github.com/yunusyosaf399/supa-model-school/pull/25).
2. DB04 Attendance — [PR #26](https://github.com/yunusyosaf399/supa-model-school/pull/26), dependent on DB03 enrollment composite key.
3. DB05 Employees/Payroll — [PR #29](https://github.com/yunusyosaf399/supa-model-school/pull/29), dependent on DB04.
4. DB06 Double-Entry Finance — [PR #30](https://github.com/yunusyosaf399/supa-model-school/pull/30), dependent on DB05/DB03.
5. DB07 Inventory/Canteen/Uniform/Transport — [PR #31](https://github.com/yunusyosaf399/supa-model-school/pull/31), dependent on DB06.
6. DB08 Approval/Permissions/Audit — [PR #32](https://github.com/yunusyosaf399/supa-model-school/pull/32), dependent on DB07.
7. DB09 Sync/Backup/Reporting — stacked draft branch after DB08.

**Do not merge/deploy blindly.** The draft SQL files are design references,
not clean Supabase CLI timestamped migrations. Review, test and reconcile
each dependency first, then create reviewed migration history against
the actual DB01/DB02 deployed baseline.

## Highest priority blockers

### 1. DB06 and DB07 cross-domain money integration
- Add DB07 typed journal kinds/sources to DB06 for POS receipts, uniform
  sales, inventory assets, COGS, production and stock writeoffs.
- Validate exact receipt amounts/costs, avoid salary/fee/inventory duplicate
  income/expense, prevent negative cash and double payments using locked
  online transactions.
- Missing stock quantities/COGS/rollup constraints and inventory cross-
  campus transfer pair reconciliation remain trusted-operation requirements.

### 2. DB08 approval engine and current role access
- Existing DB01 role CHECK is extended by DB08 source. Review all old
  policies before the DDL migration, seed role/permission definitions, map
  active staff/teacher/student guardians to the proper campus.
- Implement and test actual role grants, decision step order, current
  permissions, delegation, no-self-approval, owner thresholds and
  state changes committed with immutable audit.
- RLS deny-by-default source does NOT mean end-to-end role-scoped CRUD is
  implemented. No generic public authenticated table-write grants.

### 3. DB09 cloud feed overlap, revocation and client encryption
- Older draft PRs #12/#13 include offline-ingest and commit-ordered change
  feed mechanisms, plus earlier local Drift outbox work. The new DB09
  domain schema cannot be deployed together with these without selecting
  and reconciling ONE authoritative receipt/feed protocol and server API.
- Windows assigned-campus offline only; Android online-only. Revoke
  device/session immediately, encrypt SQLite and backups, prevent
  cross-campus read/submit, keep finance approvals pending offline.
- Test exact idempotent retry, two-session commit order, cursor apply in
  one SQLite transaction, tenant-scoped tombstones, days-long reconnect,
  conflict resolution and lost-ACK recovery.

### 4. Backup and restore
- Ensure stored backup bytes are encrypted, checksummed and include local
  outbox where relevant; cloud backup alone cannot restore private
  Storage object files or unsynced local data.
- Restore latest authoritative Supabase state first, then separately
  validate/replay legitimate backup outbox requests. Do not overwrite
  newer cloud business records. Verify backups with full restore drills.

## Local acceptance sequence (not executed)

1. Verify installed Supabase CLI version/commands via `supabase --help`
   (Supabase CLI v3 now defaults to local; remote requires explicit flags).
2. Apply reviewed DB01/DB02 baseline to disposable local Supabase and
   reconcile the actual hosted migration history.
3. Run DB03→DB09 DDL in dependency order and fix SQL parser, FK, unique,
   trigger, RLS, dangerous SECURITY DEFINER and function grants.
4. Run each domain's rollback-only fictional PostgreSQL fixture and
   static guard. Use two-campus users/teachers/HR/Owner/Accountant and
   confirm permissions deny cross-campus records.
5. Run multi-session transactions for fees/payroll/stock/ledger/approvals
   and change-feed cursor ordering; no duplicate financial posting.
6. Run Windows offline acceptance suite: encryption, outbox, Sync Now,
   auto-sync, revocation, broken network, conflicting edits and backups.
7. Check performance/indexes, security advisors and Storage policies.
8. Generate and review actual CLI-named migrations, merge reviewed
   dependency PRs in order, and deploy only with explicit approval.
9. Backfill/validate permissions, test real school data in isolation,
   then enable UI and server endpoints incrementally.

**Design progress:** 9/9 core schema domains authored. **0 remain to
design; 7 remain to integrate, test and deploy (DB03–DB09).** This does
not include unresolved implementation tasks from the 114-task backlog.
