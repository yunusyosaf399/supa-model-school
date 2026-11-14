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