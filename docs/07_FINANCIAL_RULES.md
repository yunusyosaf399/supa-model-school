# Financial rules — required invariants

- Fees generated per student + month + category + plan item with UNIQUE source key; exceptions separately identified.
- Receipts, allocations and credit applications must commit atomically and never allocate above available receipt or charge due.
- A repeated `operation_id` returns the original server result. Distinct genuine partial payments with equal amount are valid.
- Cash/bank are the only payment methods in pilot. Internal account transfer is neither revenue nor expense.
- A school-owner capital injection increases capital/cash but not operating revenue.
- Expenses crossing approval threshold remain non-posted until authorized approval.
- Reversals/adjustments preserve the original transaction, approval, reason and prior period.
- Cash closings are provisional when outbox/conflicts remain; full reconciliation requires no unresolved relevant operations.
- Per-campus reporting includes transferred debt collection responsibility without creating duplicate charges/income.
- Salary advances and subsequent recovery are not counted as two independent salary expenses.
- Inventory procurement spending differs from cost of goods sold; profit calculations require full basis and reconciliations.

Do not use binary floating point for money. Use PostgreSQL NUMERIC or integer minor units; SQLite uses integer minor units.