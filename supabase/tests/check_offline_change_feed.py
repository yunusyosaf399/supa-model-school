#!/usr/bin/env python3
"""D04-T04 source-only guardrails; NOT a Postgres execution or RLS proof."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB04_CHANGE_FEED.sql").read_text()
edge = (root / "supabase/functions/offline-pull/index.ts").read_text()
tests = (root / "supabase/tests/OFFLINE_CHANGE_FEED_INTEGRATION.sql").read_text()
ingest = (root / "supabase/drafts/DB04_OFFLINE_INGEST.sql").read_text()
schema = (root / "lib/offline/schema/campus_cache.drift").read_text()

assert set(re.findall(r"(?im)^CREATE TABLE app_private\.(\w+)\s*\(", sql)) == {
    "offline_admission_change_log"
}
assert "ENABLE ROW LEVEL SECURITY" in sql
assert "REVOKE ALL ON app_private.offline_admission_change_log" in sql
assert "FROM PUBLIC,anon,authenticated" in sql
assert "CREATE INDEX offline_admission_changes_campus_seq_idx" in sql
assert "change_seq bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY" in sql
assert "BEFORE UPDATE OR DELETE ON app_private.offline_admission_change_log" in sql
assert "AFTER INSERT OR UPDATE OR DELETE ON public.admission_applications" in sql
assert "BEFORE TRUNCATE ON public.admission_applications" in sql
assert "app_private.offline_capture_admission_change()" in sql
assert "pg_catalog.pg_advisory_xact_lock(410704,4404)" in sql
assert "v_revision := NEW.revision" in sql
assert "OLD.school_id IS DISTINCT FROM NEW.school_id" in sql
assert "NEW.revision <= OLD.revision" in sql
assert "'admission.delete'" in sql and "'deleted',true" in sql
assert "'admission.upsert'" in sql and "'applicant_name',NEW.applicant_name" in sql
assert "FOR r IN" in sql and "SELECT * FROM public.admission_applications" in sql
assert "app_private.offline_pull_admission_changes(" in sql
assert "app_private.admission_actor_allowed(" in sql
assert "d.assigned_campus_id=p_campus" in sql
assert "d.registered_user_id=p_actor" in sql
assert "dc.expires_at > pg_catalog.now()" in sql
assert "dc.credential_sha256 = pg_catalog.sha256(" in sql
assert "FOR SHARE OF d,dc" in sql
assert "school_id=p_school AND campus_id=p_campus" in sql
assert "change_seq > p_after" in sql
assert "LIMIT p_page_size + 1" in sql
assert "ORDER BY change_seq" in sql
assert "p_page_size NOT BETWEEN 1 AND 100" in sql
assert "p_after > v_max" in sql
assert "'next_cursor',v_last::text" in sql
assert "'change_seq',change_seq::text" in sql
assert "'revision',revision::text" in sql
assert "'has_more',v_count > p_page_size" in sql
assert "GRANT EXECUTE ON FUNCTION app_private.offline_pull_admission_changes" in sql
assert not re.search(r"(?im)^CREATE\s+(?:OR REPLACE\s+)?FUNCTION\s+public\.",sql)

assert 'authClient.auth.getUser(auth.slice(7))' in edge
assert "const actor = data.user.id" in edge
assert "X-Offline-Device-Proof" in edge
assert "Number.isSafeInteger(pageSize)" in edge
assert "maxInt64 = 9223372036854775807n" in edge
assert "typeof value !== \"string\"" in edge
assert "JSON.stringify" not in edge or "payload" not in edge
assert "app_private.offline_pull_admission_changes(" in edge
assert "$6::bigint" in edge and "$7::integer" in edge
assert "Cache-Control" in edge and "no-store" in edge
assert "Deno.env.get(\"SUPABASE_DB_URL\")" in edge
assert "service_role" not in edge
assert "verify_jwt = false" not in edge

for marker in (
    "SQLSTATE '23514'", "SQLSTATE '22023'", "SQLSTATE '42501'",
    "admission.delete", "admission.upsert", "Fictional B Hidden",
    "Rolled Back Example", "ROLLBACK;",
):
    assert marker in tests, marker
assert "offline_device_credentials" in ingest
assert "local_replica_metadata" in schema
print("STATIC PASS: append-only SQL change log, global commit-order lock, "
      "campus proof, lossless cursor pagination, Auth-gated Edge pull and tests.")
print("NOT VERIFIED: PostgreSQL migration, local transaction concurrency, "
      "Edge/Deno execution, client application or device encryption.")
