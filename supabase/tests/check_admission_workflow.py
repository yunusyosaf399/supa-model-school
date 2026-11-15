#!/usr/bin/env python3
"""Static admission workflow source/security checker. NOT a PostgreSQL test."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
schema = (root / "supabase/drafts/DB02_WORKFLOW_SCHEMA.sql").read_text(encoding="utf-8")
ops = (root / "supabase/drafts/DB02_ADMISSION_OPERATIONS.sql").read_text(encoding="utf-8")
api = (root / "supabase/functions/admissions/index.ts").read_text(encoding="utf-8")

new_tables = set(re.findall(r"(?im)^create table public\.(\w+)\s*\(", schema))
rls = set(re.findall(r"(?im)^alter table public\.(\w+) enable row level security;", schema))
expect_tables = {
    "admission_application_guardians",
    "school_registration_counters",
    "admission_action_events"
}
assert new_tables == expect_tables, f"Incorrect admission extension tables: {new_tables}"
assert new_tables == rls, f"Missing RLS: {new_tables - rls}"
assert "from public,anon,authenticated;" in schema
assert "unique (school_id,operation_id)" in schema
assert "one_primary_application_guardian" in schema
assert "one_parent_role_per_application" in schema
assert "one_offline_device_per_campus" not in schema

names = re.findall(r"(?im)^create or replace function app_private\.(\w+)\(", ops)
expect_functions = {
    "admission_actor_allowed", "admission_requires_principal",
    "admission_finalize", "admission_save_draft", "admission_submit",
    "admission_review"
}
assert set(names) == expect_functions, f"Incorrect private functions: {names}"
assert len(names) == len(expect_functions)
assert len(re.findall(r"security definer", ops, re.I)) == len(expect_functions)
assert ops.count("set search_path = ''") == len(expect_functions)
assert "grant execute on function app_private.admission_submit" in ops
assert "from public,anon,authenticated;" in ops
assert not re.search(r"(?im)^create or replace function public\.admission_", ops)
assert not re.search(r"(?im)^\s*grant execute.*\bto\s+(anon|authenticated)\b", ops)
assert "app_private.admission_actor_allowed" in ops
assert "p_actor" in ops and "p_operation" in ops
assert "admission_revision_conflict" not in ops  # server uses SQLSTATE
assert "Admission revision conflict" in ops
assert "Pending offline operations must be retried with the SAME" in ops
assert "jsonb_to_recordset" in ops
assert "admission_action_events" in ops
assert "admission_document_deadline_events" in ops
assert "school_registration_counters" in ops
assert "documents_state='conditional'" in ops
assert "v_need_principal:=app_private.admission_requires_principal" in ops
assert "admission_finalize(a.id,p_actor)" in ops
assert "pg_catalog.pg_advisory_xact_lock" in ops
assert "if a.documents_state='complete' and exists" in ops

assert "auth.getUser(" in api and "const actor = data.user.id;" in api
assert 'Deno.env.get("SUPABASE_DB_URL")' in api
assert 'new Pool(databaseUrl, 1, true)' in api
assert "getUuid(input.operation_id)" in api
assert api.count("conn.queryObject") == 3
assert "return respond(401" in api and "return respond(403" in api
assert "anon" not in api.lower() or "SUPABASE_ANON_KEY" in api
assert "service_role" not in api.lower()
assert "POST required" in api
print("STATIC PASS: 3 workflow tables with RLS; 6 private definer functions; 3 authenticated API actions.")
print("NOT VERIFIED: PostgreSQL parser, SQL migration, Auth, live RLS, Edge runtime, race tests or deployment.")
