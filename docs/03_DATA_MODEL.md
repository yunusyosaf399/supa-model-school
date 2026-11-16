# Data model — domain catalog (draft)

DB01 school foundation: schools, campuses, academic_years, classes, sections, user_profiles, user_roles, principal_report_permissions, school_settings, campus_settings, registered_devices.
DB02 admissions: students, guardians, student_guardians, admission_applications, student_documents, student_document_uploads, student_document_reviews, admission_document_deadline_events, student_enrollments, campus_transfer_requests; transfer_receivables follows only after DB03 fee charges.
DB03 fees: fee_categories, fee_plans, fee_plan_items, student_fee_rules, fee_discounts, fee_charges, fee_receipts, fee_allocations, student_credit_entries, fee_adjustments.
DB04 attendance: school_calendar_days, attendance_policies, attendance_duties, attendance_registers, attendance_register_events, student_attendance_marks, attendance_correction_requests, attendance_correction_decisions, staff_attendance_records, staff_attendance_correction_requests, staff_attendance_correction_decisions.
DB05 payroll: employees, employee_assignments, salary_settings, payroll_periods, payroll_entries, payroll_adjustments, salary_advances, advance_repayments, salary_payments.
DB06 money: financial_accounts, account_movements, account_transfers, expense_categories, expenses, capital_transactions, cash_closings, cash_closing_adjustments.
DB07 business: canteen_products, stock_movements, canteen_sales, uniform_materials, production_batches, finished_stock_movements, uniform_sales, vehicles, vehicle_expenses.
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
