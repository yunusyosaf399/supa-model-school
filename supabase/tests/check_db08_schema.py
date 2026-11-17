#!/usr/bin/env python3
"""DB08 static source guard. No PostgreSQL execution."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[2]
sql=(root/"supabase/drafts/DB08_APPROVALS_PERMISSIONS_AUDIT_SCHEMA.sql").read_text()
fixture=(root/"supabase/tests/DB08_APPROVALS_INTEGRATION.sql").read_text()
expected={
"db08_roles","db08_permissions","db08_role_grants","db08_user_overrides",
"db08_role_audit","db08_approval_policies","db08_approval_steps",
"db08_workflow_subjects","db08_approval_requests","db08_approval_sources",
"db08_approval_delegations","db08_approval_decisions","db08_audit_events",
"db08_document_templates","db08_notification_messages",
"db08_notification_events","db08_user_shortcuts","db08_operation_receipts"}
tables=set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(",sql))
rls=set(re.findall(r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;",sql))
assert tables==expected,tables^expected
assert rls==expected,rls^expected
assert sql.count("user_roles_role_check")>=2
for x in ("'teacher'","'driver'","'store_keeper'","'transport_manager'",
          "'vice_principal'","'parent'","'hr'"):
    assert x in sql,x
assert "UNIQUE (request_id,step_no)" in sql
assert "Self approval prohibited" in sql
assert "Approval request identity or revision invalid" in sql
assert "FOREIGN KEY(expense_request_id,school_id,campus_id)" in sql
assert "FOREIGN KEY(attendance_request_id,school_id,campus_id)" in sql
assert "FOREIGN KEY(transfer_request_id,school_id,campus_id)" in sql
assert "CHECK(num_nonnulls(" in sql
assert "source_kind='workflow' OR campus_id IS NOT NULL" in sql
assert "one_active_policy" in sql
assert "request_sha256 bytea" in sql
assert len(re.findall(r"(?m)^CREATE FUNCTION app_private\.",sql))==3
assert len(re.findall(r"(?m)^CREATE TRIGGER ",sql))==16
assert len(re.findall(r"(?m)^AS \$db08\$$",sql))==3
assert len(re.findall(r"(?m)^\$db08\$;$",sql))==3
assert len(re.findall(r"(?m)^CREATE TRIGGER \w+_no_edit\b",sql))==7
assert len(re.findall(r"(?m)^CREATE TRIGGER \w+_no_truncate\b",sql))==7
assert "FROM PUBLIC,anon,authenticated;" in sql
assert not re.search(r"(?im)^\s*CREATE POLICY ",sql)
assert not re.search(r"(?im)^\s*GRANT .* TO (anon|authenticated)\b",sql)
for marker in ("Self approval accepted","Duplicate review accepted",
               "Cross-campus approval source accepted","Immutable approval",
               "DB08 RLS not enabled","ROLLBACK;"):
    assert marker in fixture,marker
assert fixture.rstrip().endswith("ROLLBACK;")
print("STATIC PASS: DB08 18 tables + 18 RLS, expanded roles, typed approval source, "
      "3 trigger functions, 16 triggers, immutable decisions and rollback fixture")
print("NOT RUN: SQL parser, role/approval RPC, PostgreSQL fixture and RLS tests")
