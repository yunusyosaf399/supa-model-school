#!/usr/bin/env python3
"""DB07 structural source assertions. No PostgreSQL execution or role testing."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB07_INVENTORY_CANTEEN_UNIFORM_TRANSPORT_SCHEMA.sql").read_text()
fixture = (root / "supabase/tests/DB07_BUSINESS_TRANSPORT_INTEGRATION.sql").read_text()
db03 = (root / "supabase/drafts/DB03_FEES_BILLING_SCHEMA.sql").read_text()
db05 = (root / "supabase/drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql").read_text()
db06 = (root / "supabase/drafts/DB06_FINANCE_CASHBOOK_SCHEMA.sql").read_text()

tables = {
    "inventory_categories", "inventory_items", "inventory_locations",
    "inventory_suppliers", "inventory_purchase_orders",
    "inventory_purchase_lines", "inventory_goods_receipts",
    "inventory_receipt_lines", "inventory_lots",
    "inventory_transfers", "inventory_transfer_lines",
    "inventory_counts", "inventory_count_lines",
    "canteen_products", "canteen_prices", "canteen_sales",
    "canteen_sale_lines", "uniform_products", "uniform_recipes",
    "uniform_recipe_lines", "uniform_production_batches",
    "uniform_material_issues", "uniform_production_outputs",
    "uniform_sales", "uniform_sale_lines", "transport_vehicles",
    "transport_routes", "transport_route_stops",
    "transport_student_assignments", "transport_driver_assignments",
    "transport_trip_logs", "transport_maintenance_events",
    "transport_expense_links", "inventory_stock_movements",
    "inventory_movement_sources", "retail_sale_reversals",
    "db07_operation_receipts",
}
created = set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(",sql))
rls = set(re.findall(
    r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;",sql))
assert created == tables, f"DB07 table mismatch: {created ^ tables}"
assert rls == tables, f"DB07 RLS mismatch: {rls ^ tables}"
assert re.search(
    r"(?is)REVOKE ALL ON\s+public\.inventory_categories.*?"
    r"public\.db07_operation_receipts\s+FROM PUBLIC,anon,authenticated;",sql)
assert not re.search(r"(?im)^\s*CREATE POLICY ",sql)
assert not re.search(
    r"(?im)^\s*GRANT\b.+\bTO\s+(?:anon|authenticated)\b",sql)
assert not re.search(r"(?im)\b(?:float|double\s+precision|real|money)\b",
    "\n".join(line.split("--",1)[0] for line in sql.splitlines()))
assert "numeric(14,3)" in sql and "unit_cost_minor bigint" in sql
assert "UNIQUE (school_id,sku)" in sql
assert "FOREIGN KEY (lot_id,school_id,campus_id,location_id,item_id)" in sql
assert "FOREIGN KEY (purchase_line_id,school_id,campus_id,purchase_order_id,item_id)" in sql
assert "FOREIGN KEY (transfer_id,school_id)" in sql
assert "transfer_qty numeric(14,3)" in sql
assert "FOREIGN KEY (product_id,school_id,campus_id,item_id)" in sql
assert "FOREIGN KEY (uniform_product_id,school_id,campus_id,finished_item_id)" in sql
assert "FOREIGN KEY (enrollment_id,student_id,school_id,campus_id,academic_year_id,class_id)" in sql
assert "FOREIGN KEY (stop_id,school_id,campus_id,route_id)" in sql
assert "FOREIGN KEY (employee_assignment_id,school_id,campus_id,employee_id)" in sql
assert "FOREIGN KEY (expense_id,school_id,campus_id)" in sql
assert "db07_expense_campus_source_key" in sql
assert "FOREIGN KEY (financial_account_id,school_id,campus_id,payment_method)" in sql
assert "one_open_transport_route_per_student_year" in sql
assert "one_approved_uniform_recipe_per_product" in sql
assert "qty * unit_price_minor::numeric" in sql
assert "units::bigint * unit_price_minor" in sql
assert "DEFERRABLE INITIALLY DEFERRED" in sql
assert "Retail sale total must equal summed line items" in sql
assert "creation_txid bigint NOT NULL DEFAULT pg_catalog.txid_current()" in sql
assert "Retail sale lines must be posted with sale header" in sql
assert "Stock movement missing typed source" in sql
assert "Stock source must post in movement transaction" in sql
assert "num_nonnulls(" in sql
assert "PRIMARY KEY (school_id,operation_id)" in sql
assert "request_sha256 bytea" in sql
assert "FOREIGN KEY (movement_id,school_id,campus_id,item_id,movement_kind)" in sql
assert "UNIQUE (school_id,operation_id)" in sql
assert "UNIQUE (school_id,reversal_operation_id)" in sql
assert "status IN ('draft','approved','cancelled')" in sql

functions = re.findall(r"(?im)^CREATE FUNCTION app_private\.(\w+)\(\)",sql)
triggers = re.findall(
    r"(?im)^CREATE (?:CONSTRAINT )?TRIGGER (\w+)",sql)
assert len(functions) == 5,functions
assert len(re.findall(r"(?m)^AS \$\$$",sql)) == 5
assert len(re.findall(r"(?m)^\$\$;$",sql)) == 5
assert len(triggers) == 38,triggers
assert len([x for x in triggers if x.endswith("_immutable")]) == 16
assert len([x for x in triggers if x.endswith("_no_truncate")]) == 16
assert len([x for x in triggers if x.endswith("_total")]) == 2
assert "CREATE TABLE public.fee_charges" in db03
assert "CREATE TABLE public.employee_assignments" in db05
assert "CREATE TABLE public.expenses" in db06
assert "UNIQUE (id,school_id,campus_id)" in db06

for marker in (
    "\\set ON_ERROR_STOP on", "ROLLBACK;",
    "Inventory purchase automatically created cash expense",
    "Stock ledger quantities incorrect",
    "CROSS CAMPUS inventory lot",
    "CROSS CAMPUS transport route",
    "Retail sale without items accepted",
    "Canteen bank method spoofed cash account",
    "Stock movement without typed source accepted",
    "Original stock movement was mutable",
    "Retail sale evidence TRUNCATE bypass",
    "Transport maintenance created DUPLICATE expense",
    "Same retail sale reversed twice",
    "Trip with decreasing odometer accepted",
    "DB07 RLS missing",
):
    assert marker in fixture,marker
assert fixture.rstrip().endswith("ROLLBACK;")

print("STATIC PASS: 37 public tables + 37 RLS, 5 PL/pgSQL functions, "
      "38 triggers (16 immutable + 16 truncate guards), two deferred "
      "retail totals, typed stock movement sources, same-campus stock/"
      "transport/vehicle expense FKs, fake rollback fixture.")
print("NOT EXECUTED: PostgreSQL DDL, SQL fixture, payroll/fee/ledger posting, "
      "two-campus RLS, stock concurrency/COGS, refund settlements, "
      "live transport assignment, DB08 approvals or DB09 sync.")
