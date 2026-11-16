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
## DB06 chart-of-accounts and journal integrity (schema design 2026-11-16)
- One physical cash/bank account maps to one campus asset-ledger account.
  Balance is derived from debit-credit lines, not from a client-owned editable
  amount. Journal headers have typed source links and one operation UUID.
- DB03 fee assessments and DB05 payroll accruals record revenue/expense and
  receivable/payable once, distinct from later cash receipts/payments; this
  prevents cash-basis double counting.
- Every journal must have >=2 lines, equal positive debit and credit sums,
  and exactly one same-school business source at COMMIT. Source+lines may be
  inserted only in the original posting transaction; original history is
  immutable thereafter.
- School Owner capital injections/withdrawals adjust EQUITY, not revenue.
  Campus cash/bank transfers change ASSET location, not operating income.
  Salary advances are receivables, not an extra wage expense.
- Expense requests are pending until online DB08 approval. Only approved
  transactions may be posted in a future trusted RPC, with immutable audit.
- Final cash close requires no unresolved sync or pending approvals, verified
  count and denominations. Bank reconciliation matches the correct bank
  account and movement amount/direction; late bank statements cannot rewrite
  finalized history.
- **Runtime still required:** source amounts/classifications, cross-domain
  atomic posting, race-proof balances, 2-campus authorizations and full RLS.
  Source: `../docs/35_DB06_FINANCE_CASHBOOK_DESIGN.md` (review draft).
