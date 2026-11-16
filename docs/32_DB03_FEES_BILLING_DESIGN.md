# DB03 — Fee Plans, Billing, Payments and Credits (DESIGN ONLY)

**Date:** 2026-11-16  
**Status:** PostgreSQL SQL DDL drafted, not deployed or runtime-tested.  
**Source:** `supabase/drafts/DB03_FEES_BILLING_SCHEMA.sql`  
**Prerequisites:** deployed DB01 and DB02; authenticated user privileges, Principal-reviewed admission and valid student enrollment.

## Scope

DB03 defines fee assessment, student-specific overrides and scholarships,
billing, pending bank-slip claims, verified receipts, partial allocations,
credit and compensating corrections. DB06 remains the authoritative
cash/bank account/cashbook and capital/expense domain. DB08 will handle
generic approvals, audit/correction review and private family uploads.

The schema adds **18 tables** and one composite enrollment unique
constraint. Every new public table has RLS enabled and grants explicitly
revoked from PUBLIC/anon/authenticated; no financial posting operations or
data API policies are being enabled.

| Table | Role |
| --- | --- |
| `fee_categories` | School-wide tuition, transport, books/resources, admission and other categories; discountable flag |
| `fee_plans` | Class/campus/academic-year fee-plan versions and lifecycle; one active plan per class |
| `fee_plan_items` | Category-specific fee plan amounts in integer minor units |
| `fee_billing_cycles` | One campus+year+month billing boundary, open/closed |
| `student_fee_rules` | Approved category override/exemption by student enrollment |
| `fee_discounts` | Approved percentage/fixed scholarship scoped by category/enrollment |
| `fee_charges` | Immutable posted assessments: gross, discount, computed net, due date |
| `fee_charge_adjustments` | Signed, separately approved corrections; no editing charges |
| `fee_receipts` | Trusted, unique, posted cash/bank receipts, idempotent operation IDs |
| `fee_allocations` | Partial or multi-charge allocation lines against verified receipts |
| `student_credit_entries` | Signed credit/refund/reversal ledger |
| `fee_credit_applications` | Applying an approved credit against a posted charge |
| `fee_receipt_reversals` | One audited full reversal per original receipt |
| `fee_payment_submissions` | Uploaded parent bank-slip claim, pending until verified |
| `fee_collection_assignments` | History of debt collection responsibility when a campus changes |
| `admission_fee_deposits` | Cash/bank deposit for an admission applicant before Principal approval |
| `fee_receipt_counters` | School-wide receipt numbering state for future server posting |
| `fee_operation_receipts` | Immutable request SHA256 + operation UUID + server result |

## Strict accounting and billing invariants

1. **Money:** integer minor units (bigint), never floating point. PKR and
   SAR have two minor decimal places: 1,000.00 = 100,000 minor units.
   Server computes percent discount from numeric arithmetic and rounds
   once to the nearest minor unit, ties away from zero for nonnegative
   gross: `round(gross_minor::numeric * percent_bps / 10000, 0)`.
   Discount must never exceed gross.
2. **Fee plan:** fee plan belongs to a school, campus, academic year and
   specific class. Database composite foreign keys prevent plan of
   Grade 2 or another campus being used for a Grade 1 enrollment. Only
   one plan can be active for a class/year/campus at a time.
3. **Scheduled charge identity:** one charge per enrollment + month +
   category, regardless of a generated operation UUID. Manual/admission
   charges have a separate unique operation key. No double charge on
   retries or campus transfer.
4. **Discount scope:** a 50% tuition award on 1,000.00 reduces ONLY
   tuition to 500.00. It does not reduce transport or resources/books.
   Only one currently active award per enrollment/category; history of
   replaced awards persists. A new plan version does not rewrite old
   posted months.
5. **Transport rules:** one active student/category override or exemption
   per enrollment, with effective month and authorization reason.
6. **Posting and payment:** only an authenticated, authorized server
   operation may post a receipt, allocate its amount, move money in DB06
   and record the same operation UUID result in one transaction. Two
   real 200.00 partial receipts are different legitimate transactions.
   A repeat of the SAME operation UUID is not a new payment.
7. **Never overspend:** sum(receipt allocations) must not exceed receipt
   amount and sum(receipt+credit allocations) must not exceed charge
   net amount + signed adjustments. Credit applications/reversals must
   not spend the same balance twice. These SUM guards CANNOT be written
   as row-level CHECKs; future server posting RPCs must acquire row
   locks, validate balances and commit atomically, with concurrency tests.
8. **Bank proof:** a parent's uploaded receipt is PENDING until a
   separately authorized bank-review decision issues an actual
   fee_receipt; uploading a file is NEVER payment verification.
   Storage bucket and parent upload identity RLS are future DB08 work.
9. **Historical correction:** posted facts and operation results reject
   UPDATE, DELETE and TRUNCATE; reversals and adjustments are new records.
   A closed billing cycle cannot be altered by a client. The trusted
   cycle-close and correction RPCs are not yet designed.
10. **Campus transfer:** original fee_charges stay in their original
    campus/year. Collection assignment is a separate append-only record;
    no duplicate charge or revenue when the collecting campus changes.
11. **Before approval:** admission_fee_deposits link to an unapproved
    admission application (not a fabricated permanent student ID).
    Principal approval and resulting student creation stay DB02 business
    rules; deposit reconciliation/recognition requires a trusted DB03/DB06
    workflow later.
12. **Offline:** financial approvals, posting, finalized receipt numbers,
    credit application, and bank verification are NOT authorized offline.
    Windows may stage a request locally pending approval; only the
    online trusted server can finalize it. Android remains online-only.

## Schema guarantees vs later transaction rules

**DDL already expresses:** UUID/school/campus/academic-year/class/enrollment
FK containment, posted-charge immutability, unique charge source,
discount/rule shapes, nonnegative amounts, receipt numbers and operation
IDs, bank-submission state and RLS deny-by-default.

**Still requires reviewed trusted server code:** student discountable
category approval, amount calculation, effective-dated plan selection,
monthly close, duplicate-per-month job serialization, credit/receipt
over-allocation protection, account movements, approval threshold,
currency precision validation from schools, secure receipt numbering,
family bank-slip upload/download, refund and reversal balancing, school
time zone, current active role/campus validation, and change-log/sync.

No client can currently read/use DB03 tables through Data API without
additional reviewed grants and authorization procedures.

## Test plan

`supabase/tests/DB03_FEES_SCHEMA_INTEGRATION.sql` is a rollback-only test
fixture with fictional data. It checks campus FKs, class/plan matching,
tuition-scoped percentage discount, transport/resources independence,
one scheduled charge per month/category, two equal-value partial payments,
duplicate operation IDs, pending bank-slip proof, cross-campus debt
responsibility transfer, pre-approval deposit, immutability and RLS.
No real money, student or receipt is involved.

`supabase/tests/check_db03_fees.py` inspects source structure only.
Neither SQL file nor test has been executed against PostgreSQL yet.

After all nine domains are designed and reviewed, create migrations with
the installed Supabase CLI, run every schema/RLS/transaction test on an
isolated local database, review advisors and proceed to staged/live
deployment only after approval. Do not manually deploy this draft.

## Explicit dependencies and next schema

DB01 foundation → DB02 admissions → **DB03 fees** → DB06 financial
accounts/cashbook, DB08 approvals/family bank slip, DB09 sync/reporting.
The next full core schema to DESIGN is **DB04 Attendance**.

See `docs/31_SCHEMA_FIRST_ROADMAP.md` for the authoritative 9-domain
remaining-count policy.
