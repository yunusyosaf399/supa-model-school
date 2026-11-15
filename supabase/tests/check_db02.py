#!/usr/bin/env python3
"""Static DB02 student/guardian review. NOT PostgreSQL migration/RLS validation."""
import re
import sys
from pathlib import Path

source = Path(sys.argv[1] if len(sys.argv) > 1 else "supabase/drafts/DB02_admissions.sql")
sql = source.read_text(encoding="utf-8")
created = set(re.findall(r"(?im)^create table public\.(\w+)\s*\(", sql))
rls = set(re.findall(r"(?im)^alter table public\.(\w+) enable row level security;", sql))
expected = {"students", "guardians", "student_guardians",
            "admission_applications", "student_documents",
            "student_enrollments", "campus_transfer_requests"}
assert created == expected, f"Unexpected DB02 tables: {created ^ expected}"
assert created == rls, f"RLS enabled mismatch: {created ^ rls}"
assert re.search(r"create unique index students_school_registration_ci_uq\s+on public.students\s*\(school_id,\s*lower\(registration_no\)\)", sql, re.I), "Missing normalized registration uniqueness"
assert sql.count("foreign key (student_id,school_id)") >= 3, "Student relationship containment incomplete"
assert "foreign key (guardian_id,school_id)" in sql, "Guardian link must use school composite FK"
assert "references public.guardians(id,school_id)" in sql
assert "create unique index one_primary_guardian_per_student" in sql
assert "create unique index one_parent_relationship_per_student" in sql
assert "on public.student_guardians(student_id,relationship)" in sql
assert "from anon,authenticated;" in sql, "Missing direct table privilege revocations"
assert not re.search(r"(?im)^create policy \S+ on public\.(students|guardians|student_guardians)", sql), "Policies must remain deny by default until reviewed"
assert not re.search(r"(?im)^grant\s+(all|insert|update|delete|select)\s+on\s+public\.(students|guardians|student_guardians)\b", sql), "Client grants prematurely introduced"
print(f"DB02 STATIC PASS: {len(created)} public tables; all RLS enabled; scoped guardian/student relationships.")
print("NOT VERIFIED: SQL execution, Supabase Auth, row permissions, or migration deployment.")
