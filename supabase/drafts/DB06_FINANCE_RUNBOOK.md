# DB06 — Cashbook/Accounting Local Test Runbook

**Design source, not a deployable migration. Do NOT run against the live
Supa Model School project. No Flutter work is part of this change.**

## SQL dependency order

Use a disposable LOCAL Supabase/PostgreSQL test instance, with the Auth
schema and a fictional test user (`sms-adm-admin-a@example.invalid`).

1. DB01 deployed-style foundation plus academic extensions.
2. DB02 restricted admissions baseline.
3. DB03 fee/billing draft (PR #25).
4. DB04 attendance draft (PR #26).
5. DB05 employees/payroll draft (PR #29).
6. `supabase/drafts/DB06_FINANCE_CASHBOOK_SCHEMA.sql`.

The DB06 source adds same-school UNIQUE keys on existing DB03/DB05
fee and payroll source tables. It is stacked on DB05 and must never
be applied to a database without its prerequisites.

After all domains are designed, review CLI `supabase --help` and produce
migrations in the correct order. Do not invent timestamped migration names
or deploy draft source directly.

## Source and fictional local fixture

```powershell
python supabase/tests/check_db06_finance.py
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB06_FINANCE_SCHEMA_INTEGRATION.sql
```

The Python script checks SQL **text structure only**; it neither parses nor
runs PostgreSQL. The SQL fixture inserts fictional school/campus/financial
accounts and operations in a BEGIN/ROLLBACK transaction and asserts:

- All 20 public DB06 tables have deny-by-default RLS and direct anon/
  authenticated data access is absent.
- A 500.00 Owner capital injection debits cash and credits EQUITY.
  A 100.00 A-cash to B-bank transfer does not post income or expense.
  A subsequently approved 60.00 utility expense reduces the original
  cash balance from 400.00 to 340.00 after transfer.
- Correct balanced journals with matching typed sources are accepted.
  Balanced source-less journals and source-linked UNBALANCED journals
  cannot pass the deferred commit-time balance/source check.
- Duplicate source transaction and cross-campus forged asset lines fail.
- Original ledger lines and financial receipts cannot be changed or
  bulk truncated. Later transaction line injection must also fail.
- A pending expense request does not immediately create paid expense.
- Cash count with unresolved offline sync cannot be finalized.
  Cash denomination total must agree with counted cash; after final close
  neither status nor denomination evidence may silently change.
- Bank statement may be linked only to correct physical bank ledger and
  amount. Late statement imports cannot alter a finalized period.
- A closed accounting period cannot accept a new journal.
- Direct client RLS/grants are denied without any broad permissive
  policy.

**Running the SQL suite locally is NOT DONE.** Its presence in GitHub
does not establish executable schema correctness.

## Concurrency and integration tests required before deployment

These are not executed by the rollback-only fixture:

1. **Two sessions / journal origin:** Commit journal A with two lines and
   a source. In a new transaction attempt a third line or source change.
   It must fail. Duplicate UUID exact replay must return the previous
   operation result; a changed payload under same UUID must conflict.
2. **Debit/credit edge:** Two simultaneous operations on one cash account
   must not spend an unavailable balance (if negative cash forbidden).
   Posting a journal with a debit of 1 and credit of 2 or with no source
   must roll back, leaving no partial linked fee/payroll fact.
3. **Campus period and transfer:** Close campus B period while A
   attempts a transfer into B; serialize safely, no B ledger line after
   closure. A to B transfer debits/credits only asset accounts.
4. **Source semantics:** DB03 fee assessment+receipt and DB05 payroll
   accrual+salary payment must each create the correct receivable,
   liability, revenue/expense and cash accounts. Neither capital funding
   nor internal transfer creates operating income; salary advances are
   receivables, not extra wages. A single posted source cannot link twice.
5. **Cash close with sync races:** Derive pending outbox/approval counts
   from DB09/DB08, not caller JSON. Concurrent pending sync must keep close
   provisional. Denomination evidence sum must equal physical count.
6. **Bank statement races:** A bank line and a reconciliation both trying
   to finalize the same period should lock the bank account record.
   Wrong account/amount/direction/duplicate match must fail.
7. **Approval and privacy:** Current role/campus/School Owner checks for
   cash/bank movements, expenses, payment reversals and cash close.
   Regular user, campus B staff and parent may not inspect campus A
   account records. Full bank routing details must never enter the
   public data API or logs.
8. **Immutability/reversal:** Correct a past closed financial period by
   adding a NEW authorized reversal and related posting in a current open
   period; original transaction and operation receipt are preserved.
9. **Reports:** Run financial totals for school and campus; ensure
   balance sheet and cashbook derived from posted journal lines,
   gross/net fee income recognized once, salary accrual vs payment
   separated and inventory procurement not automatically cost of sales.
10. **Runtime:** Use actual PostgreSQL migration parser/DDL, local
    integration fixture, security/performance advisors, query plans,
    transaction concurrency, backups and restore checks before any
    live service is activated.

No financial Edge Function or posting RPC is authored here; all financial
tables remain inaccessible directly to client Auth and anon roles.
Service-role or DB credentials must never be embedded in Flutter apps.

## Known design gaps deliberately retained

- DB08 approval policies, thresholds and signatures.
- DB07 inventory/vehicle/canteen cost-of-goods links.
- DB09 sync checkpoints, latest cloud records and final close conflict.
- Authorization, active employee/Owner campus mapping, posting source
  amount equality, protection against overpayment and negative cash.
- Final financial reporting and external jurisdiction/tax compliance.

**Schema progress: 3 domains remain to design (DB07–DB09);
7 domains remain undeployed (DB03–DB09).**
