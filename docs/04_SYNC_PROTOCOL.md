# Offline synchronization contract — draft

**Scope:** only the registered desktop's assigned campus + minimal school reference data in SQLite. All Android writes are online.

1. A local business action and its outbox record commit atomically in SQLite with a UUID `operation_id`.
2. Client retries uploads after online detection, startup or Sync Now. Server validates authenticated user, device assignment, role/campus, current rules, and expected record revision.
3. Server writes the operation result and processed-operation receipt in ONE DB transaction, returning the same result for identical retries.
4. Server maintains durable, monotonically ordered change events. Local sync pulls by stable cursor and handles deletions/tombstones, approvals, and permission revocation.
5. Conflicting updates remain unresolved for authorized review. Never last-write-wins for financial records.
6. Pending approval is an authorization request, not an expense/payment finalization.
7. Local provisional receipts have no globally finalized receipt number. Server-confirmed receipt issued after acceptance.
8. Campus transfers and daily fully reconciled cash closings require online reconciliation and no unresolved related outbox.
9. Cursor advances only AFTER all corresponding change events are durably applied locally.
10. Device cannot switch assigned campus offline.

Server functions, permission expiry, retention and conflict schema are **not implemented** in this initial repo commit. Test retry after acknowledgement loss, concurrent payments, reconnection after several days and revocation.
## D04-T01 — SQL/Drift campus cache foundation (draft PR #8)
The local offline desktop schema now has a source-defined, single-binding school/campus/device table, campus-checked academic/student/admission/guardian/document replicas and a cursor placeholder. See `docs/19_OFFLINE_SQLITE_SCHEMA.md` on branch `db/d04-local-drift-schema`. This is **not** a persistent operation outbox and does **not** provide encryption, auth expiry, live synchronization or server permissions. Only the registered Windows PC will be allowed to open this store after device/session checks are implemented. Android and other PCs remain online-only. The schema and tests are pending developer laptop execution.

## D04-T02 — durable local operation outbox (source only)
On [draft PR #8](https://github.com/yunusyosaf399/supa-model-school/pull/8), version-2 Windows SQLite adds ordered UUID operations and append-only event history. Local admission draft edits and queued operations are committed together. Expired leases may retry the SAME UUID/payload with a new token; conflicts and delayed retries block subsequent operations, and acknowledged events remain available for audit. See [docs/20_OFFLINE_OUTBOX.md](https://github.com/yunusyosaf399/supa-model-school/blob/db/d04-local-drift-schema/docs/20_OFFLINE_OUTBOX.md). These are source implementations, **not authenticated cloud sync**; no lease, crash, SQLite migration or Flutter runtime test has passed in this environment. The code is not wired to the UI, and unencrypted local storage may not contain real child PII.

## D04-T03 — authenticated server ingestion (DRAFT SOURCE ONLY)
[PR #12](https://github.com/yunusyosaf399/supa-model-school/pull/12) adds a new private SQL ingest contract with current role/campus/registered-PC checks, hashed device-proof validation, UUID/JSON canonical request hashing, durable immutable receipts, local-to-cloud UUID mapping and cloud revision conflict rejection. It accepts only offline-created admission drafts, **not finance or offline Android writes**. The Edge route verifies the Supabase user's JWT and calls the private function with parameterized SQL. The client outbox is not yet connected and no Supabase schema is deployed. D04-T04 must implement cloud change events, cursor and local acknowledged-state reconciliation; all SQL and Edge tests must run locally before production. See `supabase/drafts/DB04_OFFLINE_INGEST_RUNBOOK.md` on the draft branch.

## D04-T04 — server-side commit-ordered admission change feed (source-only)
[Stacked draft PR #13](https://github.com/yunusyosaf399/supa-model-school/pull/13) implements a private, campus-scoped admission change log with transactional ordering using a global `pg_advisory_xact_lock` before allocating identity sequences, immutable history, upsert/delete tombstones, guarded admission revisions and a latest-state bootstrap. The authenticated `offline-pull` Edge endpoint returns bounded pages and `after_cursor`/`change_seq` as decimal strings, filtering by verified current role and registered campus device proof. The SQL fixture covers campus isolation, pagination, rollback gaps, revocation and immutability; separate-session concurrency testing remains unexecuted. Existing `local_replica_metadata.last_applied_cursor` is ONLY a placeholder. Atomic SQLite event application, conflict handling, secure device key storage and actual network syncing remain D04-T05; no live schema or Edge deployment has occurred. See `supabase/functions/offline-pull/README.md` and `supabase/drafts/DB04_CHANGE_FEED_RUNBOOK.md` on stacked branch.

## DB09 complete domain SQL source design (2026-11-17; NOT DEPLOYED)
- `supabase/drafts/DB09_SYNC_BACKUP_REPORTING_SCHEMA.sql` defines
  assigned-campus device permission/revocation; operation receipt UUID +
  SHA256, a school row-locked commit-ordered change clock/feed, tombstones,
  local-apply cursor reports, conflict and restore audit, backup manifests
  and campus-filtered reporting projections.
- Existing unmerged offline-ingest/change-feed PRs #12/#13 are a separate
  earlier implementation. Before migration decide one **authoritative**
  receipt and cloud feed schema, adapt their Edge endpoints, and remove
  duplicates. The new schema does not activate any ingest/pull endpoints.
- A cursor is persisted in SQLite in the SAME transaction as its feed page;
  only afterward should the desktop ACK to server. Device authorization
  and user's active campus role are verified on every upload and pull.
- Windows auto-sync on connectivity and manual Sync Now; Android online-only.
- Offline pending approval NEVER authorizes payment, school transfer,
  payroll or final cash closing. See `docs/38_DB09_SYNC_BACKUP_REPORTING_DESIGN.md`.
**0 core domain designs remain; 7 domains awaiting testing/deployment.**
