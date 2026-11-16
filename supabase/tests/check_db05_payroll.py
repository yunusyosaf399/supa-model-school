#!/usr/bin/env python3
"""DB05 source-only payroll/employee schema assertions. NOT PostgreSQL proof."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql").read_text()
tests = (root / "supabase/tests/DB05_PAYROLL_SCHEMA_INTEGRATION.sql").read_text()
wanted = {
    "employee_departments", "employee_positions", "employees",
    "employee_assignments", "employee_teaching_assignments",
    "payroll_components", "salary_structures", "salary_structure_lines",
    "employee_leave_requests", "employee_leave_days", "payroll_periods",
    "payroll_entries", "payroll_entry_lines", "payroll_cost_allocations",
    "payroll_adjustments", "salary_advances", "advance_repayments",
    "salary_payments", "salary_payment_reversals",
    "payroll_operation_receipts",
}
tables = set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(", sql))
rls = set(re.findall(r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;",sql))
assert tables == wanted, f"Unexpected/missing DB05 tables: {tables ^ wanted}"
assert rls == wanted, f"DB05 RLS mismatch: {rls ^ wanted}"
assert re.search(
    r"(?is)REVOKE ALL ON\s+public\.employee_departments.*?"
    r"public\.payroll_operation_receipts\s+FROM PUBLIC,anon,authenticated;",sql)
assert not re.search(r"(?im)^CREATE POLICY ",sql)
assert not re.search(r"(?im)^\s*GRANT\b.+\bTO\s+(anon|authenticated)\b",sql)
assert "UNIQUE (school_id,employee_no)" in sql
assert "UNIQUE (id,school_id,auth_user_id)" in sql
assert "one_employee_per_login_per_school" in sql
assert "FOREIGN KEY (position_id,school_id,department_id)" in sql
assert "FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)" in sql
assert "FOREIGN KEY (employee_id,school_id,teacher_user_id)" in sql
assert "FOREIGN KEY (class_id,campus_id,academic_year_id)" in sql
assert "one_open_primary_employee_assignment" in sql
assert "one_active_salary_structure_per_employee" in sql
assert "CHECK (status <> 'active' OR approved_by IS NOT NULL)" in sql
assert "FOREIGN KEY (component_id,school_id,component_kind)" in sql
assert "EXTRACT(DAY FROM payroll_month)=1" in sql
assert "UNIQUE (school_id,employee_id,payroll_month)" in sql
assert "gross_minor - regular_deductions_minor - advance_recovery_minor" in sql
assert "regular_deductions_minor + advance_recovery_minor <= gross_minor" in sql
assert "payroll_cost_allocations" in sql
assert "UNIQUE (school_id,employee_id,leave_date)" in sql
assert "UNIQUE (payroll_entry_id,advance_id)" in sql
assert "FOREIGN KEY (advance_id,school_id,employee_id)" in sql
assert "FOREIGN KEY (payment_id,school_id,employee_id)" in sql
assert "UNIQUE (payment_id)" in sql
assert "request_sha256 bytea" in sql
assert "PRIMARY KEY (school_id,operation_id)" in sql
assert len(re.findall(r"(?im)^CREATE TRIGGER db05_\w+_immutable\b",sql)) == 10
assert len(re.findall(r"(?im)^CREATE TRIGGER db05_\w+_no_truncate\b",sql)) == 10
assert "app_private.db05_reject_posted_mutation()" in sql
money_comment_free = "\n".join(l.split("--",1)[0] for l in sql.splitlines())
assert not re.search(
    r"(?im)\b(?:double\s+precision|float|real|money)\b",
    money_comment_free), "Unsafe money type"
for marker in (
    "Multi-campus employee assignments", "Cross-campus payroll",
    "Duplicate employee monthly salary", "Two partial salary payments",
    "Double recovery", "Other employee advance",
    "Duplicate leave day", "Salary component kind mismatch",
    "Immutable salary assessment", "Posted payroll receipt",
    "foreign_key_violation", "SQLSTATE '23514'", "RLS missing",
    "ROLLBACK;",
):
    assert marker in tests, f"Missing fictional test case: {marker}"
assert tests.lstrip().startswith("-- DB05")
assert "\\set ON_ERROR_STOP on" in tests
assert tests.rstrip().endswith("ROLLBACK;")
print("STATIC PASS: 20 HR/payroll tables, matching RLS, 20 financial evidence "
      "immutability/truncate guards, school-wide monthly pay identity, "
      "employee/campus scope FKs, salary advance repayment linkage and "
      "fictional rollback-only fixture.")
print("NOT RUN: PostgreSQL migrations, cashbook posting, concurrent "
      "payroll payments/advance balances, employee privacy or real HR access.")
