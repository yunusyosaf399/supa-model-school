# DB03 — Student Fees and Billing (schema design authored)

**Updated 2026-11-16 — SQL DESIGN SOURCE ONLY, NOT DEPLOYED.**

See `DB03_FEES_BILLING_SCHEMA.sql` (18 table definitions, RLS deny-by-default),
`../../docs/32_DB03_FEES_BILLING_DESIGN.md` (detailed 18-table contract),
`../tests/DB03_FEES_SCHEMA_INTEGRATION.sql` (disposable-local rollback tests)
and `../tests/check_db03_fees.py` (static checks).

## Fee domain boundary

Fee categories, campus/class/year fee plan versions, plan items, monthly
billing cycles, student-specific overrides, discounts, charges and signed
adjustments, verified receipt identities, partial allocations, student credit
ledger/application, reversals, pending bank-slip submissions, pre-approval
admission deposits, collection responsibility after campus transfer,
school-wide receipt numbering and immutable request-operation results.

**Not DB03:** financial accounts, cashbook movements/transfers, expenses,
capital, cash closing (DB06); general approvals/audit/parent upload rights
(DB08); attendance (DB04); payroll (DB05); inventory/canteen/transport fleet
(DB07); complete sync/backups (DB09).

## Required invariants

- Amounts are integer minor units; no binary floating point.
- Each scheduled charge has one student+enrollment+month+category source key.
- Fee plan, enrollment class, campus and academic year match by composite FK.
- Approved scholarship is scoped per fee category; tuition discounts must
  not change transport or books.
- Receipts, credits and allocations are different facts. Legitimate equal
  partial payment amounts are not duplicate operations.
- Bank-slip upload stays pending until verified online.
- Reversals, debt transfers, adjustments and correction events are append-only.
- Pending offline expense/payment review never becomes final posting offline.
- Charge balances and credit no-double-use require transactional row locks in
  **future trusted posting operations**, and cash movement needs DB06.
- No direct untrusted Data API table grants or live data allowed yet.

## Remaining schema design progress

Nine core database domains: DB01–DB09. DB01/DB02 baseline schemas are already
deployed. DB03 is authored as a draft. **Six full domains remain to design
(DB04–DB09), and seven domains remain undeployed (DB03–DB09).**
See `../../docs/31_SCHEMA_FIRST_ROADMAP.md`.

Do not deploy DB03 until all domain designs have been reviewed and the local
PostgreSQL/RLS and financial concurrency tests have passed.
