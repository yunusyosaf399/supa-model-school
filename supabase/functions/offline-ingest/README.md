# Offline admission ingest Edge Function — D04-T03 (source draft)

This function is NOT deployed. It accepts only a **single queued
admission.save_draft** operation from an explicitly registered, authorized
Windows campus desktop. It does NOT sync student documents, finalize admissions,
or handle any cash, payroll, fee or offline Android write.

## Authentication / security

- Keep Supabase Edge **verify_jwt = true** (default) and pass the user's live
  Supabase Auth JWT in the Authorization header. The handler independently
  calls auth.getUser(jwt), not trust user_metadata.
- Send the publishable key as apikey, never as an Authorization bearer value.
- Send X-Offline-Device-Proof: exactly 64 hexadecimal characters representing
  a securely provisioned 32-byte random device credential. The Edge handler
  NEVER logs it or sends it back. SQL stores SHA256 of the raw credential bytes
  only in unexposed app_private.offline_device_credentials.
- Device proof provision/rotation, Windows credential encryption and user
  session expiry are NOT implemented. Do not create/use real credentials yet.
- The server obtains actor UUID ONLY from verified Auth and checks actual active
  user role, registered_devices school/campus, registered_user_id, current
  offline authorization, expiry, revocation and proof for each operation.
- SQL SECURITY DEFINER is in non-exposed app_private, with search_path = '';
  EXECUTE is explicitly revoked from PUBLIC/anon/authenticated and granted
  only to service_role. Never grant client EXECUTE or expose app_private.
- SUPABASE_DB_URL is a **server-only** secret, never Flutter code or repository.

## Request (illustrative fictional UUIDs; no real pupil PII)

POST /functions/v1/offline-ingest
Authorization: Bearer USER_ACCESS_JWT
apikey: PUBLISHABLE_KEY
X-Offline-Device-Proof: [64 HEX CHARACTERS]

Body:
```json
{
  "action": "ingest_offline_draft",
  "school_id": "11111111-1111-4111-8111-111111111111",
  "campus_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "device_id": "99999999-9999-4999-8999-999999999999",
  "operation_id": "11111111-aaaa-4111-8111-222222222222",
  "local_application_id": "11111111-aaaa-4111-8111-111111111111",
  "local_revision": 1,
  "expected_cloud_revision": null,
  "payload": {
    "operation_id": "11111111-aaaa-4111-8111-222222222222",
    "local_application_id": "11111111-aaaa-4111-8111-111111111111",
    "academic_year_id": "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
    "applicant_name": "Fictional Offline Child",
    "date_of_birth": "2015-02-03",
    "previous_school": null,
    "requested_class_id": "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    "requested_section_id": null
  }
}
```

The payload field names match the current offline Flutter
OfflineOutboxRepository payload_json. The future transport must obtain
school/campus/device from its validated local assignment, not from UI text.
It must send the same operation UUID, local UUID and JSON on every retry.
Local revisions must arrive 1,2,3... without gaps.

## Success response (HTTP 200)

```json
{
  "data": {
    "status": "accepted",
    "operation_id": "11111111-aaaa-4111-8111-222222222222",
    "local_application_id": "11111111-aaaa-4111-8111-111111111111",
    "cloud_application_id": "A-SERVER-GENERATED-UUID",
    "local_revision": 1,
    "cloud_revision": 1
  }
}
```

A byte-for-byte semantic retry with the same UUID/canonical JSON produces
the same stored response; changing payload or identity with the same UUID
returns conflict. Subsequent local edits use the **same local_application_id**,
NEW operation UUID, and incrementing local_revision. The server maps them
to the saved cloud_application_id and checks optimistic cloud revision.

## Errors

- 400: malformed request; 401: no valid user session
- 403: user/campus/device/credential disabled, revoked, expired or mismatched
- 409: reused ID with different contents, local revision gap, cloud conflict
- 413: body over limit; 422: invalid business data; 500: unexpected internal
  error (no secrets, pupil PII or internal SQL returned)

Never treat a 409 as success. Keep the local outbox item in conflict and
require authorized reconciliation. Retry connectivity errors with the SAME
operation ID and original payload. Verify successful response identity and
scope before local acknowledgment (future D04-T04 sync worker).

## Limits of source implementation

The Edge function, trusted device credential provisioning, encrypted Windows
storage, local to cloud revision/ID reconciliation, download cursor, data
changes and network retry worker are NOT deployed or connected to the UI.
No endpoint can yet be called successfully against an empty Supabase schema.
See supabase/drafts/DB04_OFFLINE_INGEST_RUNBOOK.md.
