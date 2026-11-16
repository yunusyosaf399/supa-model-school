# Supabase schema workspace

Project: `uebzvfzpbqqttbqyxxos` (SUPA MODEL SCHOOL link), region `ap-south-1`.
**No school tables have been deployed yet.**

- `drafts/DB01_foundation.sql` — foundation/auth/RLS **review draft**.
- `drafts/DB02_admissions.sql` — students, conditional admissions, document uploads/reviews/deadline history **review draft**.
- `drafts/DB03_finance_design.md` — fee/cash ledgers and relationships, not SQL yet.
- `migrations/` — populated only after `supabase migration new <name>` generates approved filenames.
- `functions/` — future server operations, including payment idempotency and approvals.
- `seed/` — fictional test data only, never production students.

## Deployability checkpoints
Review explicit PK/FK, cross-campus containment, RLS+GRANT, auth bootstrap, tenant isolation, safe triggers, privilege escalation, operation IDs. Locally reset and migrate; test RLS with Owner and campus-bound users; run Supabase advisors; deploy only after review.

Draft SQL is not executable evidence. No live school records until end-to-end tests pass.
## D03-T02 documents
The `drafts/DB02_DOCUMENT_STORAGE_PLAN.md` describes future private Storage requirements; `tests/DB02_DOCUMENT_ACCEPTANCE.md` lists tests still to run locally. No Storage bucket, SQL migration, or Edge Function was deployed. The draft now has 10 RLS-enabled public DB02 tables (not 10 live tables).

## D04-T03 offline ingest (new source; NOT deployed)

- `drafts/DB04_OFFLINE_INGEST.sql`: three RLS-enabled private tables
  (device credentials, local-to-cloud admission mappings, immutable receipts)
  plus the private trusted `app_private.offline_ingest_admission_draft`
  transaction. Reuses DB01 `public.registered_devices`.
- `functions/offline-ingest/index.ts`: separate authenticated Edge handler,
  accepts only campus-scoped offline draft operations and checks a protected
  device proof. **Never** expose the DB URL/service credentials to Flutter.
- `functions/offline-ingest/README.md`: exact API envelope/receipt contract.
- `drafts/DB04_OFFLINE_INGEST_RUNBOOK.md`: local-only test and security
  prerequisites.
- `tests/OFFLINE_INGEST_INTEGRATION.sql`: fictional rollback-only SQL
  fixture for duplicate IDs, same-payload retries, conflicting revisions,
  unauthorized campus/device/user and immutable receipts.
- `tests/check_offline_ingest.py`: static review; NOT a PostgreSQL test.

The local Flutter queue is **not** connected to this endpoint. Existing real
Supabase public tables remain empty. Do not deploy a draft or register a real
school/user/device until migration, two-campus RLS and Edge integration tests
pass, Windows credential storage is encrypted, and device provisioning/
rotation/expiration are implemented and reviewed.

## D04-T04 admission change feed (source draft; not deployed)

- `drafts/DB04_CHANGE_FEED.sql` — private RLS-enabled append-only admission
  event log; AFTER INSERT/UPDATE/DELETE capture, bulk-truncation rejection,
  campus/ID immutability checks, transaction-scoped advisory commit-order
  sequencing, and latest-state backfill for preexisting admissions.
- `functions/offline-pull/index.ts` — verified-user JWT Edge handler,
  registered offline desktop proof, campus-scope checks, page sizes 1–100,
  after_cursor as a lossless decimal string and `has_more` pagination.
- `functions/offline-pull/README.md` — request/response contract, initial
  pull behavior, tombstones and local atomic-cursor application requirements.
- `tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql` — rollback-only fictional
  PostgreSQL test: campus isolation, paging, invalid/rolled-back cursor gaps,
  revision/tombstone guards, secret expiry, revocation and private grants.
- `tests/check_offline_change_feed.py` — static source review only.
- `drafts/DB04_CHANGE_FEED_RUNBOOK.md` — disposable-local database
  prerequisites and two-session commit-order concurrency test plan.

**Dependency order:** DB01 foundation → DB02 admissions → DB02 workflow →
DB02 admission operations → DB04 offline ingest → DB04 change feed.
The SQL and Edge function have NOT been deployed, and the Flutter client
has not implemented atomic event application/cursor persistence. Do not
load real pupil data until the encryption, device enrollment and
PostgreSQL/RLS/Edge runtime acceptance gates have all passed.
