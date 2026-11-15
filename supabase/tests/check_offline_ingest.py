#!/usr/bin/env python3
"""D04-T03 static checks only; not SQL execution, Auth, RLS or Edge deployment."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB04_OFFLINE_INGEST.sql").read_text()
edge = (root / "supabase/functions/offline-ingest/index.ts").read_text()
fixture = (root / "supabase/tests/OFFLINE_INGEST_INTEGRATION.sql").read_text()
client = (root / "lib/offline/offline_outbox_repository.dart").read_text()

expected_tables = {
    "offline_device_credentials", "offline_admission_mappings",
    "offline_ingest_receipts",
}
tables = set(re.findall(r"(?im)^CREATE TABLE app_private\.(\w+)\s*\(",sql))
assert tables == expected_tables, f"Unexpected private tables: {tables ^ expected_tables}"
rls = set(re.findall(r"(?im)^ALTER TABLE app_private\.(\w+) ENABLE ROW LEVEL SECURITY;",sql))
assert rls == expected_tables, f"Missing private RLS: {expected_tables-rls}"
assert "REFERENCES public.registered_devices(id)" in sql
assert "REFERENCES public.admission_applications(id,school_id,campus_id)" in sql
assert "UNIQUE (school_id,cloud_application_id)" in sql
assert "PRIMARY KEY (school_id,operation_id)" in sql
assert "credential_sha256" in sql and "pg_catalog.sha256" in sql
assert "dc.expires_at > pg_catalog.now()" in sql
assert "d.registered_user_id=p_actor" in sql
assert "d.revoked_at IS NULL" in sql and "dc.revoked_at IS NULL" in sql
assert "FOR SHARE OF d,dc" in sql
assert "app_private.admission_actor_allowed" in sql
assert "app_private.admission_save_draft(" in sql
assert "pg_catalog.pg_advisory_xact_lock" in sql
assert "v_receipt.request_sha256 IS DISTINCT FROM v_hash" in sql
assert "RETURN v_receipt.response_json" in sql
assert "p_local_revision <> v_map.last_local_revision + 1" in sql
assert "v_map.last_cloud_revision" in sql
assert "CREATE TRIGGER offline_receipt_no_update_delete" in sql
assert "REVOKE ALL ON FUNCTION app_private.offline_ingest_admission_draft" in sql
assert "GRANT EXECUTE ON FUNCTION app_private.offline_ingest_admission_draft" in sql
assert "FROM PUBLIC,anon,authenticated" in sql
assert not re.search(r"(?im)^CREATE (?:OR REPLACE )?FUNCTION public\.",sql)

assert 'authClient.auth.getUser(auth.slice(7))' in edge
assert 'const actor = data.user.id' in edge
assert 'X-Offline-Device-Proof' in edge
assert "await conn.queryObject" in edge
assert "app_private.offline_ingest_admission_draft" in edge
assert 'JSON.stringify(payload)' in edge
assert '$1::uuid' in edge and '$10::jsonb' in edge
assert "actor" in edge and "403" in edge and "409" in edge
assert 'Deno.env.get("SUPABASE_DB_URL")' in edge
assert "service_role" not in edge
assert "verify_jwt = false" not in edge
assert "getUser(" in edge
assert "offline_device_credentials" in fixture
for name in ("v_op1","v_op2","v_op3","SQLSTATE '23505'",
             "SQLSTATE '40001'","SQLSTATE '42501'","ROLLBACK;"):
    assert name in fixture, name
assert "'operation_id': op" in client
assert "'local_application_id': localId" in client
assert "'academic_year_id': draft.academicYearId" in client
assert "expectedCloudRevision" in client
assert "localRevision" in client
print("STATIC PASS: private credential/map/receipt schema, RLS, immutable receipts, actor/device checks, canonical replay hash, revision guards, Edge Auth, fixture and outbox contract.")
print("NOT EXECUTED: PostgreSQL DDL, local SQL integration, Edge runtime, device credential provisioning or Flutter network sync.")
