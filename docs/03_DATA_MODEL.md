# Data model — domain catalog (draft)

DB01 school foundation: schools, campuses, academic_years, classes, sections, user_profiles, user_roles, principal_report_permissions, school_settings, campus_settings, registered_devices.
DB02 admissions: students, guardians, student_guardians, admission_applications, student_documents, student_document_uploads, student_document_reviews, admission_document_deadline_events, student_enrollments, campus_transfer_requests; transfer_receivables follows only after DB03 fee charges.
DB03 fees: fee_categories, fee_plans, fee_plan_items, student_fee_rules, fee_discounts, fee_charges, fee_receipts, fee_allocations, student_credit_entries, fee_adjustments.
DB04 attendance: school_calendar_days, attendance_policies, attendance_duties, attendance_registers, attendance_register_events, student_attendance_marks, attendance_correction_requests, attendance_correction_decisions, staff_attendance_records, staff_attendance_correction_requests, staff_attendance_correction_decisions.
DB05 payroll: employee_departments, employee_positions, employees, employee_assignments, employee_teaching_assignments, payroll_components, salary_structures, salary_structure_lines, employee_leave_requests, employee_leave_days, payroll_periods, payroll_entries, payroll_entry_lines, payroll_cost_allocations, payroll_adjustments, salary_advances, advance_repayments, salary_payments, salary_payment_reversals, payroll_operation_receipts.
DB06 money: ledger_accounts, financial_accounts, expense_categories, expense_requests, expenses, account_transfers, capital_transactions, account_opening_entries, accounting_periods, ledger_journals, ledger_lines, ledger_reversals, ledger_source_links, cash_closings, cash_closing_counts, cash_closing_adjustments, bank_statement_lines, bank_reconciliations, bank_reconciliation_matches, financial_operation_receipts.
DB07 business: inventory_categories, inventory_items, inventory_locations, inventory_suppliers, inventory_purchase_orders, inventory_purchase_lines, inventory_goods_receipts, inventory_receipt_lines, inventory_lots, inventory_transfers, inventory_transfer_lines, inventory_counts, inventory_count_lines, canteen_products, canteen_prices, canteen_sales, canteen_sale_lines, uniform_products, uniform_recipes, uniform_recipe_lines, uniform_production_batches, uniform_material_issues, uniform_production_outputs, uniform_sales, uniform_sale_lines, transport_vehicles, transport_routes, transport_route_stops, transport_student_assignments, transport_driver_assignments, transport_trip_logs, transport_maintenance_events, transport_expense_links, inventory_stock_movements, inventory_movement_sources, retail_sale_reversals, db07_operation_receipts.
DB08 controls: approval_policies, approval_requests, approval_decisions, correction_requests, audit_events, document_templates, user_shortcuts.
DB09 sync: processed_operations, cloud_change_log, sync_conflicts, device_sync_status, backup_manifests and client-local sync_outbox/sync_state.

**Integrity:** UUID primary keys; school/campus FK containment; document and academic history; exact money in minor units or NUMERIC on cloud; unique scheduled-charge source keys, unique receipt operation IDs, unique enrollment per active academic year. Cash and bank internal transfers are not revenue.

DB01 and DB02 baseline were deployed to Supabase on 2026-11-16 through versioned migrations (see docs/27_DB02_ADMISSIONS_RESTRICTED_BACKEND.md). The original draft SQL files remain design references, NOT the authoritative migration history. DB03 fee SQL is now authored but undeployed; see docs/32_DB03_FEES_BILLING_DESIGN.md.
## Conditional admissions (D03-T02 draft)
The SQL draft separates admission approval status from document completeness. Missing required documents can result in **conditional approval with a recorded deadline**, not deletion. Requirement rows are linked to a campus/application; upload metadata and decisions retain history and deadline changes are auditable. These are SQL-design invariants, **not deployed behavior**. Actual file access requires separate private Storage bucket policies and server-authorized operations.

## Admission workflow source additions (D03-T03, not deployed)
- `admission_application_guardians` holds guardian data in drafts before student creation.
- `school_registration_counters` provides a school-wide serial allocated within a trusted finalization transaction.
- `admission_action_events` tracks create/update/submit/review operation UUIDs and statuses for auditable retries.
- `admission_applications` receives intended class/section and client operation ID fields via `DB02_WORKFLOW_SCHEMA.sql`.
- Private transactional operations live in `DB02_ADMISSION_OPERATIONS.sql` and an authenticated server wrapper lives in `supabase/functions/admissions/index.ts`. Neither was deployed; all real PostgreSQL and Edge tests remain pending.

## Schema-first scope update (2026-11-16)
The nine-domain catalog DB01–DB09 defines the schema count, separate from
114 implementation tasks. DB01/DB02 are baseline-deployed; DB03 has an
18-table fee and billing DDL draft; **6 complete core domains remain to
design (DB04–DB09), and 7 remain undeployed (DB03–DB09).**
See docs/31_SCHEMA_FIRST_ROADMAP.md. Names like DB05_UI_PREFERENCES and DB09
Owner dashboard are smaller auxiliary works, not full completion of their
respective payroll or sync/backup domains. Finance cash/bank movements belong
to DB06, not the DB03 fee collection and student debt ledger.

## DB04 attendance schema — design authored, NOT deployed (2026-11-16)
The stacked DB04 draft contains 11 deny-by-default RLS tables, first-period
and optional after-break session attendance, same-school/campus/year/class/
section enrollment FK guards, daily teacher duties, immutable initial
student/staff marks and approved correction event history. It depends on
DB03's composite enrollment UNIQUE constraint. Staff user records will be
linked to the future DB05 employee/assignment model. The currently deployed
DB01 role constraint does not yet include a full Teacher role; the authorizing
server RPCs are not implemented. See docs/33_DB04_ATTENDANCE_DESIGN.md.
**5 domains remain to design (DB05–DB09), 7 remain undeployed (DB03–DB09).**

## DB05 employee/payroll schema — design authored, not deployed (2026-11-16)
Stacked DB05 draft contains 20 new public RLS-denied HR/payroll tables,
employee/campus/position/teaching-assignment FKs, one original salary per
employee per school month, earned/deducted component snapshots, signed
adjustments, immutable salary payments and advance recoveries. The active
Teacher role in deployed DB01, approved salary posting, salary confidentiality,
leave-day validation, allocation/recovery sums and DB06 linked account
movements remain pending. See docs/34_DB05_EMPLOYEES_PAYROLL_DESIGN.md.
**4 full core schemas remain to design (DB06–DB09); 7 remain undeployed
(DB03–DB09). No Flutter source changes or hosted SQL deployment.**

## DB06 double-entry finance/cashbook — design authored, NOT deployed (2026-11-16)
20 tables and 20 RLS statements define school chart-of-accounts with
cash/bank physical asset mapping; paired debit/credit posting lines, typed
same-school DB03/DB05 accrual and payment sources, operating expense claims,
capital and internal transfers, cash closings, bank statement reconciliation
and immutable request receipts. Balanced/source-linked journals must validate
at COMMIT. For details see `docs/35_DB06_FINANCE_CASHBOOK_DESIGN.md`.
**3 full schemas remain to design (DB07–DB09), 7 remain undeployed
(DB03–DB09).** No Flutter code or new hosted Supabase SQL.

## DB07 Inventory/Canteen/Uniforms/Transport — SQL design, NOT deployed (2026-11-16)
37 school/campus scoped tables for purchase and goods receipt, stock lot
and signed movement evidence, store transfers, stock counts, two retail
sale channels, uniform material/production outputs, vehicles, routes, real
DB03 enrolled students, DB05 driver assignments, DB06 posted vehicle
expense linking, and reversals. Source movements/retail totals are checked
by deferred triggers. See `docs/36_DB07_BUSINESS_TRANSPORT_DESIGN.md`.
**2 full core domains remain to design (DB08–DB09); 7 are still undeployed
(DB03–DB09).** DB06 journal kinds must be extended for inventory/COGS.
No Flutter code or new live SQL in this schema-design session.
