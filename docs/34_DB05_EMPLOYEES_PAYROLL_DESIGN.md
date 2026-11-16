# DB05 — Employees, Campus Assignments, Payroll and Salary Advances

**Date:** 2026-11-16
**Status:** SQL schema source authored for review. NOT deployed. NO Flutter source changes.
**Branch:** `db/db05-employees-payroll-schema-20261116` stacked on DB04 draft PR #26.
**SQL:** `supabase/drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql`

## Goals / explicit boundaries

One school with several campuses. Employees are **school-wide identities**
with dated assignments in one or more campuses. Payroll has one original
monthly salary assessment per employee across the entire school, even when
the employee teaches or works at multiple campuses. Separate cost allocation
does not generate additional salary or move cash.

Money is integer minor units (BIGINT), based on the school currency code
in DB01. For example, 1,000.00 PKR or SAR = 100,000 minor units if currency
has two decimal places. A later approved currency-minor-unit policy is
needed for currencies with other scales; never use binary floating point.

DB05 records salary liabilities and advance obligations. DB06 will provide
the authoritative cash/bank-account ledger; DB08 will own configurable
approval rules and privacy/audit policies; DB09 will own sync/reporting.
Neither an offline pending salary request nor a parent/operator-uploaded
record is a posted cash/bank movement.

## Twenty database tables

| Table | Responsibility |
| --- | --- |
| `employee_departments` | School-scoped HR departments and codes |
| `employee_positions` | Positions tied to school/department |
| `employees` | School-wide employee identity, optional Auth login, employment status |
| `employee_assignments` | Dated campus/department/position allocation and primary status |
| `employee_teaching_assignments` | Campus/year/class/section/subject plus verified employee Auth identity |
| `payroll_components` | Earning and deduction component catalog |
| `salary_structures` | Approved, versioned salary basis and assigned paying campus |
| `salary_structure_lines` | Exact component salary rates in minor units |
| `employee_leave_requests` | Staff leave applications and reviewed decision status |
| `employee_leave_days` | Unique recorded paid/unpaid leave date, never duplicated between campuses |
| `payroll_periods` | Campus/month approval/closing lifecycle |
| `payroll_entries` | One school-wide salary assessment per employee/month, computed net |
| `payroll_entry_lines` | Earning/deduction salary component snapshots |
| `payroll_cost_allocations` | Gross salary allocation across participating campuses; NOT another payment |
| `payroll_adjustments` | Immutable signed salary corrections and bonuses |
| `salary_advances` | Approved advance loan/receivable, separate from wage expense |
| `advance_repayments` | Advance recovery attached to salary entry and employee |
| `salary_payments` | Partial/full salary payment evidence, one operation UUID each |
| `salary_payment_reversals` | One immutable reversal per original payment |
| `payroll_operation_receipts` | Exact request digest and accepted operation outcome for future idempotent service |

## Workflows and exact financial examples

A school employee can work 60% at campus A and 40% at campus B. Both
assignments remain in HR history. A single monthly salary payroll entry
of 1,000.00 is assessed by the paying campus. Cost allocation entries
may attribute 600.00 to A and 400.00 to B without issuing a second salary.

Example monthly payroll (two-decimal currency):

| Fact | Amount |
| --- | ---: |
| Gross salary | 1,000.00 |
| Regular deductions | 100.00 |
| Repayment of previously issued advance | 150.00 |
| Net salary payable | **750.00** |
| First legitimate payment | 300.00 |
| Second legitimate payment | 450.00 |
| Outstanding net salary after both payments | 0.00 |

A 400.00 salary advance was disbursed earlier. Recovering 150.00 of that
advance reduces the outstanding advance from 400.00 to 250.00 and reduces
cash salary payable for the current month. It **must not create a second
salary expense or a second cash disbursement**. The actual advance cash
payment and each payroll payment will each need a DB06 account movement,
posted in the same trusted online transaction as the corresponding record.

## Invariants expressed in SQL

1. Every employee belongs to exactly one school. Employee number is
   school-unique, and Auth login mapping is optional and unique per
   school. No password, bank account secret, raw ID document or medical
   data is stored on the general employee row.
2. Campus assignments and positions have composite school/campus/
   department/employee FKs. Primary open assignment is unique. Historical
   dated assignments are not overwritten when an employee moves.
3. Teaching assignments require a real employee mapped to an Auth
   identity, plus matching school/campus/class/section/year. DB01's
   currently deployed user role whitelist lacks `teacher` and must be
   expanded and authorized before live teacher attendance access.
4. A salary structure has an approved version and at most one active
   structure for an employee. Salary component line kind matches the
   earning/deduction catalog by FK.
5. Payroll period has a first-of-month date, statuses draft/calculated/
   approved/closed, and audit actor/timestamps for approved/closed.
6. **One original payroll entry per (school_id,employee_id,payroll_month)**
   regardless of its paying campus; duplicates are rejected even with
   different operation UUIDs. Gross minus regular deductions minus
   advance recovery is computed at database level.
7. Multiple salary payments are permitted, each with a unique operation
   ID. One salary payment can be reversed at most once, by a separate
   immutable row. Original payments/assessments are never edited.
8. A repayment references an advance of the **same employee and school**
   and a payroll entry of the **same employee/school/campus**.
9. A single calendar date's leave cannot be recorded twice for the same
   school employee, even when they work at multiple campuses.
10. Ten tables of posted evidence block UPDATE/DELETE and TRUNCATE:
    leave days, payroll entries/details, cost allocations, adjustments,
    advances/repayments, salary payments/reversals, operation receipts.
11. All 20 tables have RLS enabled. Direct privileges to PUBLIC, anon
    and authenticated are revoked. No unsafe client-facing posting
    policy, bulk read of salary or unrestricted RPC is added.

## Rules that REQUIRE trusted server transactions

SQL foreign keys alone do **not** enforce financial aggregation or
real-time employment authorization. Before live use, implement and test:

- Verify current Owner/HR/Accountant/Principal authorization, campus
  scope, effective-dated employment contract and salary structure,
  and actual payroll period eligibility at posting time.
- Ensure salary structure version/date activation, employee primary
  assignment, work-share 10000 basis points, and cost allocations don't
  overlap or exceed 100% across effective dates.
- Reconcile salary structure lines to gross/regular deduction snapshots
  and attendance/paid leave/overtime basis, using policy approved at
  the time, not a future-edited config.
- Require all payroll cost allocation amounts sum exactly to posted
  gross; no negative or duplicate campus cost share.
- Serialize/check cumulative advance recoveries so they never exceed
  original advance; sum of recoveries for each salary entry must equal
  `advance_recovery_minor`, not post an additional wage expense.
- Reconcile effective net payable with approved signed adjustments;
  serialize partial payments, ensure amount paid minus reversals does
  not exceed the final payable after adjustments. Test two concurrent
  payment requests to prevent race-condition overpayment.
- Require every salary advance disbursement and salary payment to
  create the correct cash/bank movement in DB06 in the same transaction,
  with matching currency, school and operation UUID.
- Ensure leave dates fall within the requested period and only
  approved leave appears as a paid leave day; reject double time
  entries/duplicate salary deductions.
- If attendance, leave, advances or pay rates are corrected after
  payroll closure, issue future authorized adjustment/reversal, not a
  rewrite to posted closed month.
- Enforce strict HR salary privacy; teachers and employees only see
  explicitly authorized own records, never a school-wide payroll dump.
  User-editable JWT metadata may not authorize any payroll query.
- Record exact request SHA256 and result in `payroll_operation_receipts`
  in the same database transaction; reject reused operation IDs with
  changed payload and return stored response for exact retries.
- Financial approvals must never finalize offline. The assigned-campus
  Windows application may stage requests locally; Android is online-only.

These are **not implemented in this schema source**, and the source is
NOT a production-ready payroll system.

## Verification

- `supabase/tests/DB05_PAYROLL_SCHEMA_INTEGRATION.sql`: isolated, fictional
  BEGIN/ROLLBACK fixture for multi-campus assignments, teaching identity,
  salary component kinds, leave, school-wide monthly payroll uniqueness,
  cross-campus FK guards, payroll cost splits, advance recovery/owner,
  partial payments, exact receipt UUIDs, immutable postings and 20 RLS
  table checks.
- `supabase/tests/check_db05_payroll.py`: static source structure guard.
- `supabase/drafts/DB05_PAYROLL_RUNBOOK.md`: local PostgreSQL and
  concurrency acceptance instructions.

**PostgreSQL/Edge/authorization tests NOT executed. No hosted Supabase
migrations or Flutter code changes.**

## Schema-first progress

9 domains total. DB01 and DB02 baseline deployed; DB03, DB04 and DB05
authored but not deployed. **4 full schemas remain to design: DB06–DB09.
7 domains await deployment: DB03–DB09.**

**Next: DB06 — Cash/bank accounts, transfers, expense and closing ledger.**
