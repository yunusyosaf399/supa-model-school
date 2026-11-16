#!/usr/bin/env python3
"""DB04 attendance schema source guard. NOT a PostgreSQL execution test."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB04_ATTENDANCE_SCHEMA.sql").read_text()
fixture = (root / "supabase/tests/DB04_ATTENDANCE_SCHEMA_INTEGRATION.sql").read_text()
db03 = (root / "supabase/drafts/DB03_FEES_BILLING_SCHEMA.sql").read_text()

tables = {
    "school_calendar_days", "attendance_policies", "attendance_duties",
    "attendance_registers", "attendance_register_events",
    "student_attendance_marks", "attendance_correction_requests",
    "attendance_correction_decisions", "staff_attendance_records",
    "staff_attendance_correction_requests",
    "staff_attendance_correction_decisions",
}
created = set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(", sql))
assert created == tables, f"Unexpected DB04 tables: {created ^ tables}"
rls = set(re.findall(r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;", sql))
assert rls == tables, f"Missing RLS: {rls ^ tables}"
assert re.search(
    r"(?is)REVOKE ALL ON\s+public\.school_calendar_days"
    r".*?public\.staff_attendance_correction_decisions"
    r"\s+FROM PUBLIC,anon,authenticated;", sql
)
assert "db03_enrollment_finance_scope_unique" in db03
assert "FOREIGN KEY (enrollment_id,student_id,school_id,campus_id," in sql
assert "REFERENCES public.student_enrollments(" in sql
assert "id,student_id,school_id,campus_id,academic_year_id,class_id)" in sql
assert "FOREIGN KEY (class_id,campus_id,academic_year_id)" in sql
assert "FOREIGN KEY (calendar_day_id,school_id,campus_id," in sql
assert "FOREIGN KEY (duty_id,school_id,campus_id,academic_year_id," in sql
assert "v_register_section IS DISTINCT FROM v_enrollment_section" in sql
assert "NEW.attendance_date < v_admitted" in sql
assert "NEW.attendance_date > v_ended" in sql
assert "NEW.marked_by IS DISTINCT FROM v_actor" in sql
assert "v_teacher IS DISTINCT FROM NEW.taken_by" in sql
assert "CREATE UNIQUE INDEX one_active_attendance_policy_per_campus_year" in sql
assert "UNIQUE NULLS NOT DISTINCT" in sql
assert "session_kind IN ('first_period','after_break')" in sql
assert "after_break_enabled boolean NOT NULL DEFAULT false" in sql
assert "NEW.session_kind='after_break'" in sql
assert "v_day_kind NOT IN ('instructional','exam')" in sql
assert "OLD.status='locked'" in sql
assert "NEW.revision<>OLD.revision+1" in sql
assert "new_status IN ('draft','submitted','locked')" in sql
assert "mark_status IN ('present','absent','late','excused','leave','sick')" in sql
assert "effective_revision_after bigint" in sql
assert "FOREIGN KEY (request_id,mark_id,school_id,campus_id,approved_status)" in sql
assert "FOREIGN KEY (request_id,record_id,school_id,campus_id,approved_status)" in sql
assert len(re.findall(r"(?im)^CREATE FUNCTION app_private\.db04_\w+\(\)",sql)) == 4
assert len(re.findall(r"(?im)^CREATE TRIGGER db04_\w+_no_mutate\b",sql)) == 8
assert len(re.findall(r"(?im)^CREATE TRIGGER db04_\w+_no_truncate\b",sql)) == 8
assert len(re.findall(r"(?im)^CREATE TRIGGER ",sql)) == 19
assert sql.count("ENABLE ROW LEVEL SECURITY;") == 11
assert "FROM PUBLIC,anon,authenticated;" in sql
assert not re.search(r"(?im)^\s*GRANT\s+.+\s+TO\s+(anon|authenticated)\b",sql)
assert not re.search(r"(?im)^CREATE POLICY ",sql)
assert not re.search(r"(?im)^CREATE OR REPLACE FUNCTION public\.",sql)

for marker in (
    "ROLLBACK;", "CROSS SECTION", "CROSS CAMPUS",
    "first_period", "after_break", "Duplicate first-period",
    "Holiday student register accepted", "Original mark overwritten",
    "Approved status different", "Immutable staff attendance",
    "Correction evidence TRUNCATE", "RLS incomplete",
    "foreign_key_violation", "SQLSTATE '23514'",
    "Create fictional LOCAL Auth test user first",
):
    assert marker in fixture, marker
assert "\\set ON_ERROR_STOP on" in fixture
assert fixture.rstrip().endswith("ROLLBACK;")
print("STATIC PASS: 11 tables, 11 deny-by-default RLS tables, "
      "8 append-only UPDATE/DELETE guards + 8 TRUNCATE guards, "
      "3 scope validation triggers, enrollment/class/calendar/duty "
      "FKs, student/staff correction source and rollback-only tests.")
print("NOT VERIFIED: PostgreSQL syntax/execution, RLS with campus roles, "
      "authorized teacher roster, posting/approval RPC, DB05 employee linkage, "
      "full timetable, offline sync or dashboard source.")
