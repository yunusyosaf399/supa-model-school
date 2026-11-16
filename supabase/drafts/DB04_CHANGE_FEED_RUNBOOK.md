# DB04 — admission change log and cursor test runbook

**Source only. Do not execute against live Supabase.** This file belongs to
a stacked branch on top of D04-T03 draft PR #12. Nothing is deployed.

## SQL dependency chain

Run on a disposable LOCAL Supabase/PostgreSQL database only, after creating
fictional users in Auth and reviewing each script:

1. `supabase/drafts/DB01_foundation.sql`
2. `supabase/drafts/DB02_admissions.sql`
3. `supabase/drafts/DB02_WORKFLOW_SCHEMA.sql`
4. `supabase/drafts/DB02_ADMISSION_OPERATIONS.sql`
5. `supabase/drafts/DB04_OFFLINE_INGEST.sql`
6. `supabase/drafts/DB04_CHANGE_FEED.sql`

Before producing deployable migrations, use the locally installed Supabase CLI
`supabase migration new <descriptive-name>` per its current `--help`
instructions. Do not invent a migration filename, deploy review SQL
without testing, or manually alter the hosted school's database.

## Tests (local only)

```powershell
python supabase/tests/check_offline_change_feed.py
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql
```

The SQL fixture requires local fictional user
`sms-adm-admin-a@example.invalid`. It exercises an empty page, a three-item
A/B/A cross-campus sequence, one-item pagination, no-op repeated fetch,
updates, revision guard, tombstone, rolled-back insert gap, forged cursor,
wrong proof, wrong campus, immutable change events and revoked desktop.
It wraps all fixture operations in BEGIN/ROLLBACK. Running it without a local
Postgres cluster and its prerequisite schema will fail.

## Additional separate-session concurrency test (manual)

Use a **fresh local test database** with two authenticated service writers.
First make two draft applications in two different campuses and note
the last server cursor. In SQL session A:

```sql
BEGIN;
UPDATE public.admission_applications
SET applicant_name='Test Writer A', revision=revision+1
WHERE id='<fictional-campus-a-admission-uuid>'::uuid;
-- KEEP THIS TRANSACTION OPEN. It holds the change-log advisory lock.
```

In session B:
```sql
BEGIN;
UPDATE public.admission_applications
SET applicant_name='Test Writer B', revision=revision+1
WHERE id='<fictional-campus-b-admission-uuid>'::uuid;
-- This waits for A's global change-log advisory lock.
COMMIT;
```

While A remains open, B must not publish a later change_seq; an authorized
reader must not advance past A's uncommitted row. Commit A; B should complete.
Both events must now arrive in increasing change_seq order when each
authorized campus fetches from its previous cursor. Also test an explicit
ROLLBACK in session A before releasing B.

Do NOT run that concurrency example on an active production database.

## Bootstrap and safety checks

- On an isolated database, create an admission before installing
  `DB04_CHANGE_FEED.sql`. The migration backfills its latest state as an
  `admission.upsert` record. Verify no duplicate rows and no omission during
  concurrent migrations.
- Check `has_table_privilege` and `has_function_privilege` for anon and
  authenticated: direct private SELECT/EXECUTE must be denied.
- Edge Auth must verify actual user JWT with `getUser`; never accept a
  service_role/publishable token as user identity.
- Confirm `app_private` stays out of Supabase Data API exposed schemas and
  that registered PC proof, expiry, revocation, campus ownership and current
  Auth roles are enforced.
- Check PostgreSQL planner/index performance under large log rows, and review
  retention strategy (event log is append-only until a separate checkpoint
  design exists).
- Perform a full Windows enrolled-device integration and encryption review
  before ingesting any real student records.

## Known incomplete work

The offline-pull Edge route has no deployed URL. No Flutter HTTP client or
atomic SQLite event-apply worker currently consumes these pages; the existing
`local_replica_metadata(last_applied_cursor)` is unused. No offline student,
guardian, document, payroll, fee, or cash replication exists. D04-T05 is the
integration and device-test task; separate module tasks own any additional
data replication. Zero live PostgreSQL migration/test actions were performed.
