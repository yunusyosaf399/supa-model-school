# D04-T03 — Offline ingest private SQL / device proof runbook

**Status: source authored and structurally reviewed. NOT EXECUTED, DEPLOYED OR
PRODUCTION APPROVED.**

## Why separate from DB01 device registration

DB01 already defines public.registered_devices and prevents more than one
active offline desktop per campus. D04-T03 reuses it. Three private tables
add security/durability without exposing extra Data API endpoints:

- app_private.offline_device_credentials: device UUID, SHA256(raw 32-byte
  proof), expiry and revocation. Credential itself remains protected on device.
- app_private.offline_admission_mappings: immutable pairing from local draft
  UUID to cloud admission UUID with last accepted local/cloud revisions.
- app_private.offline_ingest_receipts: one receipt per (school,operation UUID),
  exact request hash, accepted local/cloud identities and durable response.
  Receipts are append-only via trigger and contain no pupil names.

Each offline operation is ONE PostgreSQL function call and transaction. The
server verifies current Auth actor + school/campus membership, registered
desktop ID/owner, current enabled assignment, non-expired device proof,
unmodified canonical request, ordered local revision and cloud optimistic
revision BEFORE saving a draft. A school-scoped transaction advisory lock
serializes concurrent offline requests in v1; a durable receipt guarantees
lost-ACK retries do not apply the operation twice.

This is a **source design for a secure ingest**. A local school/campus FK
or Flutter UI filter is not an authorization mechanism.

## Dependency order (offline local test only)

Use a disposable LOCAL Supabase project or database with Auth schema:

1. supabase/drafts/DB01_foundation.sql
2. supabase/drafts/DB02_admissions.sql
3. supabase/drafts/DB02_WORKFLOW_SCHEMA.sql
4. supabase/drafts/DB02_ADMISSION_OPERATIONS.sql
5. supabase/drafts/DB04_OFFLINE_INGEST.sql

These are REVIEW DRAFTS, not generated migration files. For a deployable
migration, run the installed Supabase CLI's documented commands locally,
create new migrations with "supabase migration new", then review schemas,
run SQL tests and RLS advisors before publishing. Never paste these drafts
directly into the live school SQL Editor without local verification.

## Tests

1. First create fictional local Auth users
   sms-adm-admin-a@example.invalid and
   sms-adm-accountant-b@example.invalid (see existing admission test runbook).
2. Execute all prerequisite draft SQL locally in the order above.
3. Execute the rollback-only suite with
   psql -X -v ON_ERROR_STOP=1 -f supabase/tests/OFFLINE_INGEST_INTEGRATION.sql
4. Run python supabase/tests/check_offline_ingest.py.
5. Run existing DB01/DB02/Admission workflow SQL tests and RLS tests.
6. Verify no client role has table access or direct EXECUTE on app_private
   ingestion functions; verify negative role/campus/device proofs.
7. Test concurrent identical UUID requests in **separate sessions**; test
   ambiguous network timeout and stale JWT/device revocation; verify response
   mapping and no repeated admission rows/receipts.
8. Run Supabase advisors; verify private schema is NOT exposed in Data API.
9. Verify the Edge function in a disposable LOCAL environment with a signed
   user JWT, using the X-Offline-Device-Proof header. This is distinct from
   the SQL integration suite and has NOT run.

The fixture uses a hard-coded, intentionally non-secret 32-byte test proof.
Never reuse it for a production PC. Production enrollment requires trusted
credential issuance and rotation; secure Windows key storage, local SQLite
encryption and backup/recovery; device/session revocation and expiration.

## Known limits and dependencies

- V1 supports admission.save_draft for drafts initially created offline. It
  rejects imported existing-cloud drafts and all financial operations.
- The existing admission workflow supports zero guardians in draft; guardian
  admission data, documents and Principal approval are different operations
  and are NOT available from this offline ingest endpoint.
- The backend validates 1,2,3 local revision sequence and compares each
  current cloud revision to the last accepted result. External cloud changes
  cause conflict, never silent last-write-wins.
- The Flutter outbox currently stores queued operations but has NO network
  dispatch, verified response handling, cloud ID mapping or cursor pull.
- D04-T04 must add durable change log/cursor and local response reconciliation;
  D04-T05 must test full offline vertical slice on authorized Windows PC.
- No production data, secret, SQL migration, Edge deployment, service keys,
  or GitHub Actions runs are part of this task.
