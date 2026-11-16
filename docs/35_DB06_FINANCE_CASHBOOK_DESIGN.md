# DB06 — School Accounts, Double-Entry Cashbook, Expenses and Reconciliation

**Design date:** 2026-11-16
**Status:** PostgreSQL SQL DESIGN ONLY. NOT DEPLOYED. No Flutter work.
**SQL:** `supabase/drafts/DB06_FINANCE_CASHBOOK_SCHEMA.sql`
**Dependency:** DB01/DB02 baseline + stacked DB03 fee, DB04 attendance and DB05 payroll draft schemas.
**Currency:** Single school currency from DB01; exact BIGINT minor units for all monetary figures. No exchange-rate conversion or payment gateway in v1.

## One authoritative accounting model

The **only monetary journal** is `ledger_journals` with two or more
`ledger_lines`. A physical cash/bank balance is derived by summing
(debit_minor - credit_minor) on the mapped ASSET ledger account, not stored
as a separately changeable cashbook balance. This is the basis for
per-campus daybook, school-wide statements, fee/salary payments and
bank reconciliation.

Every posted journal must have:
- Exactly one type-specific source in `ledger_source_links` (with a real,
  same-school FK to a DB03/DB05/DB06 business fact).
- **At least 2 lines and equal, positive debit and credit totals**,
  checked by deferred PostgreSQL constraint triggers at transaction commit.
- A currently OPEN accounting period for the initiating campus and every
  campus represented by a ledger line. A cross-campus transfer touches
  both campuses and must not post into a closed period.
- Lines and source link inserted within the **original posting database
  transaction** (checked by stored transaction ID); never added after a
  journal is committed.
- An immutable operation ID and future SHA256 replay receipt in the
  same trusted online posting transaction. Client-side retries cannot
  post again simply because the network acknowledgment was lost.

These rules provide structural safeguards. **They do not replace a
trusted posting operation.** No cloud financial RPC is implemented here.

## DB06 tables — 20 new public tables

| Table | Responsibility |
| --- | --- |
| `ledger_accounts` | School chart of accounts: asset, liability, equity, income, expense, with school/campus scope |
| `financial_accounts` | Physical cash or bank accounts mapped to campus asset accounts, masked bank display reference only |
| `expense_categories` | Operating expense, inventory procurement and capital-asset categories |
| `expense_requests` | Unposted expense requests with pending/approved/rejected/cancelled status |
| `expenses` | Immutable authorized paid expense with approved request and physical account FK |
| `account_transfers` | Same-school physical-account internal transfers, including different campuses |
| `capital_transactions` | Owner injection/withdrawal linked to a cash/bank account and EQUITY |
| `account_opening_entries` | Explicit reviewed opening balances; one per physical account |
| `accounting_periods` | Per-campus accounting month open/closed, one per month |
| `ledger_journals` | Immutable journal header and typed posting source, linked to period |
| `ledger_lines` | Debit and credit postings, scoped to school/campus/chart account |
| `ledger_reversals` | One auditable full reversal of an earlier journal |
| `ledger_source_links` | Exactly one typed business source per journal, no duplicate source posting |
| `cash_closings` | Per-campus/account/date provisional or final daily cash close |
| `cash_closing_counts` | Immutable counted denominations and computed subtotals |
| `cash_closing_adjustments` | New approved posting correcting a past cash close |
| `bank_statement_lines` | Unique imported bank statement entries without account secrets |
| `bank_reconciliations` | Bank reconciliation by account and statement end date |
| `bank_reconciliation_matches` | One-to-one statement-to-ledger-line matching |
| `financial_operation_receipts` | Immutable request SHA256, operation UUID and response for trusted idempotency |

The migration additionally adds six same-school UNIQUE keys needed by
source FKs to DB03/DB05 tables plus typed keys for fee assessment,
fee adjustment, payroll accrual and payroll adjustment. Existing
historical journal data is never rewritten by these source links.

## Examples (currency with two decimals)

### Example A — Fee charged, then paid

Charging tuition of 1,000.00 is **not** a cash receipt:

| At fee assessment | Debit | Credit |
| --- | ---: | ---: |
| Student receivable | 1,000.00 | — |
| Tuition revenue | — | 1,000.00 |

When a parent pays 600.00:

| At receipt | Debit | Credit |
| --- | ---: | ---: |
| Cash or bank account | 600.00 | — |
| Student receivable | — | 600.00 |

Income is recognized once at fee assessment. Cash collection is a reduction
of the receivable, **not another tuition revenue**. For a discount, assess
the correct DB03 net amount and approved revenue/discount lines. Overpaid
money belongs to the student-credit liability; refund requires its own
balanced reversal/posting. Future trusted DB03+DB06 operations must
enforce exact source amounts and account kinds.

### Example B — Internal transfer, campus A to B

Move 100.00 from Campus A cash to Campus B bank:

| Account | Debit | Credit |
| --- | ---: | ---: |
| Campus B bank asset | 100.00 | — |
| Campus A cash asset | — | 100.00 |

The overall school's cash+bank balance remains unchanged.
**No revenue and no expense** arises from this transfer.

### Example C — Owner capital

Inject 500.00 owner capital into cash:

| Account | Debit | Credit |
| --- | ---: | ---: |
| Cash asset | 500.00 | — |
| Owner equity | — | 500.00 |

It increases cash/equity but **not school operating income**. Owner
withdrawal is the reverse equity/cash classification.

### Example D — Salary and advance

Payroll accrual (gross 1,000.00, 100.00 regular deductions,
150.00 salary advance recovered) must use approved payable, deduction
liability and advance receivable ledger accounts. Current net payable is
750.00. Paying the worker 300.00 and later 450.00 reduces salary payable
and bank/cash, not salary expense a second time.

Issuing an earlier 400.00 salary advance was a **receivable** and cash/bank
outflow, not another wage expense. The future posting service must
reconcile DB05 `advance_repayments` and the accounting liabilities so
the recovery cannot be counted twice.

## Expense and cash closing policy

- An `expense_request` pending offline approval is **not an expense
  payment**. Approval threshold, Owner-configurable approvers and online
  decision audit belong in DB08. Only a trusted online posting operation
  can insert immutable `expenses`, a balanced journal and a matching
  operation receipt with the same authorized source.
- School equipment/inventory procurement is classified separately from
  general operating expense; whether it becomes an asset or inventory
  cost is defined with DB07, not counted automatically as COGS.
- A campus cash count captures the book balance, actual counted cash,
  denomination evidence and signed variance. A discrepancy requires
  a reason. The cash count remains **provisional** while relevant
  pending offline sync/approvals exist. Finalization requires both
  counts zero, a verifier and denomination total matching counted cash.
  The trusted service must obtain counts from authoritative DB09 sync
  and DB08 approval state, not user-entered numbers.
- Closed cash statements and final bank reconciliations are protected
  against updates/deletes and late denomination/statement injections.
  Corrections post NEW reviewed journal+cash-closing adjustment records.
- Bank statement matching checks the actual physical bank's ledger
  account and debit/credit direction/amount. A statement line cannot
  be matched twice, and final reconciliation requires no unmatched
  imported statement entries through the statement end date.

## Permissions and privacy

All 20 new public tables have RLS **enabled** and direct grants to
`anon`/`authenticated` explicitly revoked. This schema creates **no**
generic SELECT policy or privileged client RPC. No `SECURITY DEFINER`
function is added to a public exposed API. Every DB06 integrity function
uses `search_path = ''` and is a database trigger only.

In the eventual service, authenticate actor and validate CURRENT school,
campus and permitted role per action. Principal access to financial details
is Owner-controlled; campus Accountant can work only in assigned campus.
School-wide Owner can approve transfers; one campus's cash details cannot
leak to another campus. Bank reference fields are display-only masked
values, not private banking credentials.

Offline Windows may stage a local pending request, but it can never
declare a cash movement posted, approve an expense, close a financial day,
or issue a final receipt offline. Android remains online-only in v1.

## Remaining server transaction work (not in schema)

1. Bind each source amount and journal account classification to
   fee charges, receipt allocations/refunds, payroll entries/payments,
   salary advances, capital and expense categories; reject inflated,
   swapped or missing source amounts.
2. Ensure one authorized journal and response per operation UUID across
   DB03, DB05, DB06, DB08 domains in one transaction. Enforce exact
   replay request hash, not UUID alone.
3. Lock balance, payment and credit rows to prevent overspending, negative
   unavailable cash, duplicate fee collections/advance recoveries and
   concurrent salary overpayment.
4. Reconcile opening balances and bank account actual balances to
   asset ledger snapshots. No app-owned mutable account balance cache.
5. Preserve and report reversal causality, original prior-period journal,
   source-specific refund status and closed-period adjustments.
6. Implement approval threshold, delegated roles, two-campus access and
   expenses/transfer/cash close workflow with DB08.
7. Implement DB07 stock and production COGS journal types and links,
   with no inventory purchase automatically classified as COGS.
8. Implement DB09 secure sync, pending operation checks, bank statement
   storage privacy and projections for Owner dashboard.
9. Test cross-session cash transfer and journal posting/period closure
   races, bank import/finalization, and duplicated operation requests.
10. Decide whether audit-grade financial reporting needs broader
    accounting controls/tax rules for each eventual jurisdiction.

## Verification status

- SQL design: `supabase/drafts/DB06_FINANCE_CASHBOOK_SCHEMA.sql`
- Rollback-only fake-data PostgreSQL fixture:
  `supabase/tests/DB06_FINANCE_SCHEMA_INTEGRATION.sql`
- Static source checker: `supabase/tests/check_db06_finance.py`
- Disposable-local test runbook:
  `supabase/drafts/DB06_FINANCE_RUNBOOK.md`

PostgreSQL DDL, SQL test fixtures, RLS role exercise, concurrency, posting
services and actual school cashbook balances are **NOT EXECUTED**.
No live Supabase SQL deployment or Flutter changes.

## Domain progress

Of 9 core schema domains, DB01+DB02 baseline are deployed, DB03–DB06
have design source but are NOT deployed. **3 full schema domains still
need design: DB07, DB08 and DB09. 7 remain undeployed: DB03–DB09.**

**Next DB07 — Canteen, Uniform Production, Inventory and Vehicles.**
