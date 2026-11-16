# D04-T04 — Ordered admission change feed and campus sync cursor

**Status: SQL/Edge/test sources committed, NOT yet run or deployed.** This is
not an end-to-end synchronization feature. The app UI remains preview-only.
D04-T03 is a prerequisite and is currently draft PR #12.

## Supported scope and strong rules

- **One registered Windows desktop, one assigned campus.** Android and all
  other PCs are online-only. Every pull rechecks the **verified** Auth user,
  actor role, device ID, assigned campus, device secret, expiration/revocation.
- The feed includes only **public.admission_applications** changes
  (create/update/delete) and a conservative allowlist of admission attributes.
  Student/guardian/document/financial tables are **NOT** in this change feed.
  No student-document binaries, guardian contact records or general SQL rows
  are included.
- It is **read-only to the device**. Direct client access to the private
  event table or SQL function is forbidden by privilege revocations. SQL RLS
  is enabled for defense-in-depth. Functions live in non-exposed app_private.
- Each committed INSERT/UPDATE/DELETE produces an event using an AFTER ROW
  trigger. A guard rejects admission scope/id reassignment, updates that do
  not increment the admission revision, and TRUNCATE (which bypasses row
  triggers). DELETE is a tombstone, not silent removal.
- The migration backfills the latest state for admissions already present
  when the trigger is installed, under the same migration transaction.
  Historical changes before installation are NOT reconstructed.
- The change log is immutable/append-only, with no automatic retention or
  deletion. Production retention and resnapshot need a separately reviewed
  policy before long-term volume grows.

## Why a plain BIGSERIAL is not enough

PostgreSQL sequence allocation order is not commit order: transaction A can
allocate ID 10 and remain uncommitted while transaction B allocates ID 11
and commits. If a client reads 11 and advances its cursor, A can commit
later and event 10 would be permanently skipped.

The capture trigger therefore acquires the **same transaction-scoped global
advisory lock** `pg_advisory_xact_lock(410704,4404)` **before** inserting into
the identity-backed event table. No writer can allocate the next event
sequence until the previous event-writing transaction commits or rolls back.
This trades cross-campus write throughput for correctness in v1. Sequence
numbers may still have gaps after rollback, so a cursor is the **last seen
committed event ID**, never number-of-events or an assumed contiguous offset.

All admission changes must use the same trigger. Do not add an unlogged
bulk-update path, disable triggers, or backfill directly around the lock.

## Endpoint

`POST /functions/v1/offline-pull`

- Authorization: Bearer a **valid user access token**, not a publishable key.
- apikey: configured publishable key.
- X-Offline-Device-Proof: 64-character hex string representing the protected
  registered desktop credential. Never print, cache insecurely or log it.
- Body (fictional IDs only):

```json
{
  "action": "pull_admission_changes",
  "school_id": "11111111-1111-4111-8111-111111111111",
  "campus_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "device_id": "99999999-9999-4999-8999-999999999999",
  "after_cursor": "0",
  "page_size": 50
}
```

The request's after_cursor MUST be a **decimal STRING** representing a
nonnegative signed-64-bit integer. This prevents loss of precision in JS.
Use "0" on a fresh empty-campus pull (subject to initial snapshot mapping).
The service rejects negative/future cursors, nonnumeric values, excessive
page sizes and unauthorized campus/device claims. The maximum page_size is
100.

Example successful response:

```json
{
  "data": {
    "school_id": "11111111-1111-4111-8111-111111111111",
    "campus_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    "events": [
      {
        "change_seq": "101",
        "event_type": "admission.upsert",
        "application_id": "aaaaaaaa-0000-4000-8000-000000000001",
        "revision": "2",
        "payload": {
          "id": "aaaaaaaa-0000-4000-8000-000000000001",
          "applicant_name": "Example Student (fictional)",
          "revision": "2"
        }
      }
    ],
    "next_cursor": "101",
    "has_more": false
  }
}
```

The payload's actual allowlisted attributes also include academic year,
class/section, optional student ID, birth date, previous school, admission/
approval/document states, conditional due date and updated timestamp. Date
strings use ISO 8601. **Real student data must not pass until encryption,
verified registration/device credential provisioning and permissions tests
are complete.**

The reply contains at most page_size events and next_cursor is the ID of
the last **returned** event. An empty batch returns the incoming cursor and
has_more=false. A longer tail sets has_more=true and the client requests
another page after applying the current one. Cross-campus sequence gaps
are intentional.

## Local persistence contract (NOT implemented in Flutter yet)

`lib/offline/schema/campus_cache.drift` already includes
`local_replica_metadata(last_applied_cursor)`, currently an unused placeholder.
For D04-T05, implement a single SQLite transaction that:
1. Verifies the signed-in user, device assignment and campus, and checks the
   response school/campus equal the pinned local school/campus.
2. Checks each event is ordered, has change_seq strictly greater than the
   stored cursor, and maps the **cloud** admission UUID to an existing local
   provisional UUID only if the accepted D04-T03 receipt authorizes it.
3. Upserts admission data only where no unsynced local edit will be overwritten.
   Revision conflicts must retain the outbox payload and stop cursor advance.
4. Applies tombstones carefully (do not delete local unsynced children,
   documents or records without verified policy).
5. Advances `last_applied_cursor` to next_cursor inside that **same local
   transaction**, only after every event has been safely persisted.

After a crash before commit, the cursor does NOT advance; replaying the same
events is safe. Never save next_cursor before data or delete unsynced data.
The HTTP dispatcher, encrypted local SQLite, cloud-ID mapping, cursor apply,
full initial snapshot, and conflict reconciliation remain D04-T05/future work.
No second SQL schema is deployed or connected to a real student directory.

## Files added

- `supabase/drafts/DB04_CHANGE_FEED.sql` — event table, capture guard/triggers,
  initial latest-state backfill, authorized private paginated reader.
- `supabase/functions/offline-pull/index.ts` — verified-user Edge handler,
  device-proof header, bounded decimal-string cursor, safe SQL parameters.
- `supabase/tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql` — rollback-only fixture:
  empty stream, campus A/B isolation, pagination, bigint string response,
  update, deletion, rollback gap, invalid cursors, immutable events, revoked PC.
- `supabase/tests/check_offline_change_feed.py` — static source review.
- `supabase/drafts/DB04_CHANGE_FEED_RUNBOOK.md` — test and merge gating.

## Verification and deployment gate

1. Clone the dependent branch and use a **disposable LOCAL Supabase PostgreSQL**
   that has Auth schema and fictional local Auth users.
2. Validate DB01, DB02, workflow and D04-T03 SQL first; apply D04_CHANGE_FEED
   via reviewed local migration after existing schemas are in place.
3. Run `python supabase/tests/check_offline_change_feed.py`.
4. Run `psql -X -v ON_ERROR_STOP=1 -f
   supabase/tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql`.
5. Run separate concurrent writer/readers in different PostgreSQL sessions to
   verify a held transaction A cannot cause a later cursor to skip its event.
6. Test a pre-existing admission before installing the trigger; verify
   one latest-state backfill event.
7. Run RLS/grants tests as authenticated user and two assigned campuses;
   test credential rotation, revocation, JWT expiry and a forged cursor.
8. Compile/invoke offline-pull Edge Function locally and check 400/401/403/
   422/500 error handling. Keep `verify_jwt=true`.
9. Review Supabase security/performance advisors, Data API exposed schemas
   and actual hosted credentials before considering deployment.

No SQL migration or functions have been deployed to the connected live
Supabase project. No GitHub Actions have run.
