#!/usr/bin/env python3
"""DB09 static source guard. Does not test actual sync/recovery."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[2]
sql=(root/"supabase/drafts/DB09_SYNC_BACKUP_REPORTING_SCHEMA.sql").read_text()
fixture=(root/"supabase/tests/DB09_SYNC_BACKUP_INTEGRATION.sql").read_text()
expected={
"db09_device_authorizations","db09_device_access_events",
"db09_operation_receipts","db09_change_clocks","db09_cloud_changes",
"db09_tombstones","db09_device_cursors","db09_sync_conflicts",
"db09_conflict_resolutions","db09_sync_runs","db09_backup_destinations",
"db09_backup_manifests","db09_backup_artifacts","db09_restore_sessions",
"db09_restore_check_events","db09_report_definitions","db09_report_snapshots",
"db09_device_reassign_events"}
tables=set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(",sql))
rls=set(re.findall(r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;",sql))
assert tables==expected,tables^expected
assert rls==expected,rls^expected
assert "db09_device_school_campus_unique" in sql
assert "FOREIGN KEY(device_id,school_id,campus_id)" in sql
assert "PRIMARY KEY(school_id,operation_id)" in sql
assert "request_sha256 bytea" in sql
assert "last_seq bigint" in sql
assert "ON CONFLICT(school_id)" in sql
assert "RETURNING last_seq INTO NEW.change_seq" in sql
assert "CREATE TRIGGER db09_change_commit_order" in sql
assert "PRIMARY KEY(school_id,change_seq)" in sql
assert "audience IN ('school','campus')" in sql
assert "change_kind IN ('upsert','delete','revoke')" in sql
assert "Cursor rollback or scope change forbidden" in sql
assert "Device not authorized for campus cursor" in sql
assert "conflict_kind IN" in sql
assert "snapshot_sha256 bytea" in sql
assert "outbox_pending integer" in sql
assert "encrypted boolean NOT NULL DEFAULT true CHECK(encrypted)" in sql
assert "pending_outbox_replayed" in sql
assert "is_demo boolean NOT NULL DEFAULT false" in sql
assert len(re.findall(r"(?m)^CREATE FUNCTION app_private\.",sql))==3
assert len(re.findall(r"(?m)^CREATE TRIGGER ",sql))==20
assert len(re.findall(r"(?m)^AS \$db09\$$",sql))==3
assert len(re.findall(r"(?m)^\$db09\$;$",sql))==3
assert len(re.findall(r"(?m)^CREATE TRIGGER \w+_no_edit\b",sql))==9
assert len(re.findall(r"(?m)^CREATE TRIGGER \w+_no_truncate\b",sql))==9
assert "FROM PUBLIC,anon,authenticated;" in sql
assert not re.search(r"(?im)^\s*CREATE POLICY ",sql)
assert not re.search(r"(?im)^\s*GRANT .* TO (anon|authenticated)\b",sql)
for marker in ("CROSS CAMPUS device cursor accepted","Duplicate operation UUID",
               "Cloud change history mutable","restore","DB09 RLS missing","ROLLBACK;"):
    assert marker in fixture,marker
assert fixture.rstrip().endswith("ROLLBACK;")
print("STATIC PASS: DB09 18 tables + 18 RLS, scoped device and operation receipts, "
      "row-locked change sequence, immutable evidence and backup/restore fixture")
print("NOT RUN: PostgreSQL migrations, sync operations, RLS, concurrency, restore")
