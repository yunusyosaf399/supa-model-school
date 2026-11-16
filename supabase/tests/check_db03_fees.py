#!/usr/bin/env python3
"""DB03 DESIGN source structure check — not PostgreSQL syntax/runtime verification."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB03_FEES_BILLING_SCHEMA.sql").read_text()
tests = (root / "supabase/tests/DB03_FEES_SCHEMA_INTEGRATION.sql").read_text()
wanted = {
    "fee_categories","fee_plans","fee_plan_items","fee_billing_cycles",
    "student_fee_rules","fee_discounts","fee_charges",
    "fee_charge_adjustments","fee_receipts","fee_allocations",
    "student_credit_entries","fee_credit_applications",
    "fee_receipt_reversals","fee_payment_submissions",
    "fee_collection_assignments","admission_fee_deposits",
    "fee_receipt_counters","fee_operation_receipts",
}
created = set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(",sql))
assert created == wanted, f"Missing or extra tables: {created.symmetric_difference(wanted)}"
rls = set(re.findall(r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;",sql))
assert rls == wanted, f"Missing or extra RLS clauses: {rls.symmetric_difference(wanted)}"
assert re.search(r"(?is)REVOKE ALL ON\s+public\.fee_categories.*?public\.fee_operation_receipts\s+FROM PUBLIC,anon,authenticated;", sql)
assert "UNIQUE (id,student_id,school_id,campus_id,academic_year_id,class_id)" in sql
assert "REFERENCES public.student_enrollments(" in sql
assert "id,student_id,school_id,campus_id,academic_year_id,class_id)" in sql
assert "FOREIGN KEY (fee_plan_id,school_id,campus_id,academic_year_id,class_id)" in sql
assert "CREATE UNIQUE INDEX one_active_fee_plan_per_class" in sql
assert "CREATE UNIQUE INDEX one_scheduled_fee_per_student_month_category" in sql
assert "CREATE UNIQUE INDEX one_manual_fee_source_operation" in sql
assert "CREATE UNIQUE INDEX one_active_student_discount_per_category" in sql
assert "CREATE UNIQUE INDEX one_active_student_fee_rule_per_category" in sql
assert "gross_minor - discount_minor" in sql
assert "percent_bps BETWEEN 0 AND 10000" in sql
assert "discount_minor <= gross_minor" in sql
assert "payment_method IN ('cash','bank')" in sql
assert "status IN ('pending','verified','rejected')" in sql
assert "UNIQUE (school_id,receipt_no)" in sql
assert "UNIQUE (school_id,operation_id)" in sql
assert "PRIMARY KEY (school_id,operation_id)" in sql
assert "request_sha256 bytea" in sql
assert "credit_entry_id" in sql and "fee_credit_applications" in sql
assert "fee_receipt_reversals" in sql and "fee_collection_assignments" in sql
assert "admission_fee_deposits" in sql
assert "next_serial bigint" in sql
assert "CHECK (delta_minor<>0)" in sql
assert "is_discountable boolean" in sql
assert "FOREIGN KEY (verified_receipt_id,school_id,student_id)" in sql
assert "FROM PUBLIC,anon,authenticated" in sql
assert not re.search(r"(?im)^\s*CREATE POLICY\s+.*\s+USING\s*\(\s*true\s*\)",sql)
assert not re.search(r"(?im)^\s*GRANT\s+.*\s+TO\s+(anon|authenticated)\b",sql)
assert "real" not in re.findall(r"(?im)\b(?:float|double precision|money)\b",sql)
assert len(re.findall(r"(?im)^CREATE TRIGGER \w+_immutable\b",sql)) == 10
for item in ("UNIQUE","foreign key","discount","partial", "rollback",
             "CROSS CAMPUS","RLS","posted fee", "bank submission"):
    assert item.lower() in tests.lower(), f"Test evidence missing: {item}"
assert "ROLLBACK;" in tests and "\\set ON_ERROR_STOP on" in tests
print("STATIC PASS: 18 fee tables, 18 RLS statements, 10 journal immutability guards, cross-campus enrollment/plan FKs, operation idempotency model and test source.")
print("NOT VERIFIED: SQL runtime, signed money totals, concurrent allocations, financial posting approval/RPC, encrypted bank-slip files or Supabase migration.")
