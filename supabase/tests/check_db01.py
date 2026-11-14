#!/usr/bin/env python3
"""Structural checks for the UNDEPLOYED DB01 SQL draft (not PostgreSQL tests)."""
from pathlib import Path
import re
import sys

filename = Path(sys.argv[1] if len(sys.argv)>1 else "supabase/drafts/DB01_foundation.sql")
sql = filename.read_text(encoding="utf-8")
tables = set(re.findall(r"(?im)^create table public\.(\w+)\s*\(", sql))
rls = set(re.findall(r"(?im)^alter table public\.(\w+) enable row level security;", sql))
assert tables, "No DB01 tables found"
assert tables == rls, f"RLS mismatch: missing {tables-rls}; unknown {rls-tables}"
assert "role_permissions" in tables and "user_roles" in tables
assert "app_private.is_school_owner(school_id)" in sql, "Owner-check helper absent"
assert re.search(r"create policy school_setting_read.*?using\s*\(app_private\.is_school_owner\(school_id\)\);", sql, re.I | re.S), "School settings too broad"
assert not re.search(r"create policy\s+\S+\s+on\s+public\.user_roles\s+for\s+(insert|update|delete|all)\b",sql,re.I), "Role mutation policy found"
assert not re.search(r"grant\s+(?:all|insert|update|delete)\s+on\s+public\.user_roles\s+to\s+(?:authenticated|anon)",sql,re.I), "Role write grant found"
assert "SECURITY DEFINER" in sql.upper(), "Security helper review unexpectedly absent"
print(f"STATIC PASS: {len(tables)} tables, {len(rls)} RLS ENABLE statements, no direct role mutation policy")
print("WARNING: this does not execute PostgreSQL or prove RLS isolation.")
