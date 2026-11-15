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
