# DB03 — Fee and finance domain: design-only

**No SQL has been generated for DB03 yet.** Depends on verified DB01 and DB02.

Required entities: fee_categories, fee_plans, fee_plan_lines, student_fee_rules, fee_discounts, fee_charges, fee_receipts, fee_allocations, student_credit_entries, fee_adjustments, financial_accounts, account_movements, account_transfers, expense_categories, expenses, cash_closings, and capital_transactions.

## Invariants
- Unique scheduled charge key: student + billing month + category + plan line; manual exceptions use a separate source.
- Student-specific transport and discount scope; category-level discount exact rounding.
- Receipt identity separate from bank/cash posting and allocation.
- Equal-value legitimate partial payments are not duplicates; identical retried operation IDs must return original result.
- Credit balances may never be consumed twice. Post and allocate in one server transaction.
- Transfer responsibility for debt between campuses without creating a new charge.
- Cashbook account transfers are paired and not recognized as income.
- Pending offline expenses that require approval must not be posted.
- Corrections and closed-day changes are new audited events, not editing historical receipts.

## Next tasks
Design FKs and unique indexes, authorize server posting functions, tests for concurrent writes, return-value idempotency and RLS; draft and review DB03 SQL only after DB01/DB02 have passed local migration checks.
