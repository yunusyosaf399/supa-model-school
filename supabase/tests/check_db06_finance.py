#!/usr/bin/env python3
"""DB06 accounting design source guard. NOT PostgreSQL/ledger runtime proof."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[2]
sql = (root / "supabase/drafts/DB06_FINANCE_CASHBOOK_SCHEMA.sql").read_text()
test = (root / "supabase/tests/DB06_FINANCE_SCHEMA_INTEGRATION.sql").read_text()
db03 = (root / "supabase/drafts/DB03_FEES_BILLING_SCHEMA.sql").read_text()
db05 = (root / "supabase/drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql").read_text()

tables = {
    "ledger_accounts", "financial_accounts", "expense_categories",
    "expense_requests", "expenses", "account_transfers",
    "capital_transactions", "account_opening_entries",
    "accounting_periods", "ledger_journals", "ledger_lines",
    "ledger_reversals", "ledger_source_links", "cash_closings",
    "cash_closing_counts", "cash_closing_adjustments",
    "bank_statement_lines", "bank_reconciliations",
    "bank_reconciliation_matches", "financial_operation_receipts",
}
created = set(re.findall(r"(?im)^CREATE TABLE public\.(\w+)\s*\(", sql))
rls = set(re.findall(r"(?im)^ALTER TABLE public\.(\w+) ENABLE ROW LEVEL SECURITY;", sql))
assert created == tables, f"DB06 table mismatch: {created ^ tables}"
assert rls == tables, f"DB06 RLS mismatch: {rls ^ tables}"
assert re.search(
    r"(?is)REVOKE ALL ON\s+public\.ledger_accounts"
    r".*?public\.financial_operation_receipts\s+FROM PUBLIC,anon,authenticated;", sql)
assert not re.search(r"(?im)^\s*CREATE POLICY\s+",sql)
assert not re.search(r"(?im)^\s*GRANT\s+.*\s+TO\s+(?:anon|authenticated)\b",sql)
assert "account_type IN ('asset','liability','equity','income','expense')" in sql
assert "FOREIGN KEY (ledger_account_id,school_id,campus_id,ledger_account_type)" in sql
assert "UNIQUE (ledger_account_id)" in sql
assert "from_account_id<>to_account_id" in sql
assert "'owner_injection','owner_withdrawal'" in sql
assert "expense_kind IN ('operating','inventory_procurement','capital_asset')" in sql
assert "status IN ('pending','approved','rejected','cancelled')" in sql
assert "CHECK ((debit_minor>0 AND credit_minor=0)" in sql
assert "credit_minor>0 AND debit_minor=0" in sql
assert "v_rows<2 OR v_debit<=0 OR v_debit<>v_credit" in sql
assert "Posted journal missing trusted source link" in sql
assert "CREATE CONSTRAINT TRIGGER db06_journal_balanced_header" in sql
assert "CREATE CONSTRAINT TRIGGER db06_journal_balanced_lines" in sql
assert sql.count("DEFERRABLE INITIALLY DEFERRED") == 2
assert "creation_txid bigint NOT NULL DEFAULT pg_catalog.txid_current()" in sql
assert "Cannot append to a previously posted journal" in sql
assert "Journal source link must commit with its header" in sql
assert "UNIQUE (school_id,operation_id)" in sql
assert "FOREIGN KEY (journal_id,school_id,journal_kind)" in sql
assert "num_nonnulls(" in sql
assert "db06_fee_receipt_school_key" in sql
assert "db06_fee_adjustment_school_key" in sql
assert "db06_payroll_entry_school_key" in sql
assert "db06_payroll_adjustment_school_key" in sql
assert "fee_charge_id uuid UNIQUE" in sql
assert "payroll_entry_id uuid UNIQUE" in sql
assert "journal_kind='fee_assessment'" in sql
assert "journal_kind='payroll_accrual'" in sql
assert "db06_salary_payment_school_key" in sql
assert "db06_salary_advance_school_key" in sql
assert "db06_admission_deposit_school_key" in sql
assert "FROM PUBLIC,anon,authenticated" in sql
assert "Unmatched bank statement line blocks final reconciliation" in sql
assert "Late bank import would change finalized statement" in sql
assert "Cash denomination count only allowed before final close" in sql
assert "Bank statement/ledger account or amount mismatch" in sql
assert "FOREIGN KEY (ledger_line_id,school_id)" in sql
assert "Cannot post journal into closed accounting period" in sql
assert "Ledger line campus period is not open" in sql
assert "unresolved_sync_count=0 AND pending_approval_count=0" in sql
assert "variance_minor bigint GENERATED ALWAYS AS" in sql
assert "subtotal_minor bigint GENERATED ALWAYS AS" in sql
assert "status IN ('provisional','final')" in sql
assert "Final bank reconciliation or identity cannot change" in sql
assert "Accounting period may only be closed once" in sql
assert "UNIQUE (original_journal_id)" in sql
assert "UNIQUE (reversal_journal_id)" in sql
assert "amount_minor bigint NOT NULL CHECK (amount_minor>0)" in sql
assert "request_sha256 bytea NOT NULL" in sql

triggers = re.findall(r"(?im)^CREATE (?:CONSTRAINT )?TRIGGER (\w+)\b",sql)
assert len(triggers) == 43, len(triggers)
assert len(re.findall(r"(?im)^AS \$\$\s*$",sql)) == 11
assert len(re.findall(r"(?im)^\$\$;\s*$",sql)) == 11
assert len([n for n in triggers if n.endswith("_immutable")]) == 13
assert len([n for n in triggers if n.endswith("_no_truncate")]) == 16
assert all(token in db03 for token in (
    "CREATE TABLE public.fee_receipts", "CREATE TABLE public.admission_fee_deposits"))
assert all(token in db05 for token in (
    "CREATE TABLE public.salary_payments", "CREATE TABLE public.salary_advances"))

for mark in (
    "Capital injection into Campus A cash",
    "Internal cross-campus cash transfer",
    "PENDING expense request incorrectly became a payment",
    "Cashbook totals wrong", "CROSS CAMPUS",
    "Duplicate transfer source",
    "Orphan journal accepted", "Unbalanced ledger accepted",
    "Mismatched bank statement",
    "Cash closing finalized despite PENDING SYNC",
    "Final bank reconciliation reopened",
    "Late bank statement import changed a final reconciliation",
    "Late cash denomination insert after final close accepted",
    "New journal accepted in CLOSED period",
    "DB06 incomplete RLS", "SQLSTATE '23514'",
    "ROLLBACK;",
):
    assert mark in test, f"Missing test source: {mark}"
assert "\\set ON_ERROR_STOP on" in test
assert test.rstrip().endswith("ROLLBACK;")
print("STATIC PASS: 20 DB06 tables + 20 RLS, 41 guards/triggers, "
      "deferred balanced and source-linked double-entry journals, "
      "immutable posted evidence, cross-campus money routing, "
      "cash-close sync rule and fake rollback fixture.")
print("NOT EXECUTED: PostgreSQL SQL parser, multi-session cash/transfer posting, "
      "DB03/DB05 business posting, DB08 approvals, DB09 offline sync, "
      "live financial balances and production migration.")
