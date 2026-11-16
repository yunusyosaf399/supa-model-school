# Supabase schema workspace

Project: `uebzvfzpbqqttbqyxxos` (SUPA MODEL SCHOOL link), region `ap-south-1`.
**Live status 2026-11-16:** DB01 school foundation and DB02 admissions baseline have been deployed, with RLS enabled. See docs/27_DB02_ADMISSIONS_RESTRICTED_BACKEND.md. The new DB03 fee schema is DESIGN ONLY and has not been deployed.

- `drafts/DB01_foundation.sql` — foundation/auth/RLS **review draft**.
- `drafts/DB02_admissions.sql` — students, conditional admissions, document uploads/reviews/deadline history **review draft**.
- `drafts/DB03_finance_design.md` — fee/billing design overview; `drafts/DB03_FEES_BILLING_SCHEMA.sql` defines 18 draft DB03 tables, still UNDEPLOYED. DB06 will cover cash/bank account movements.
- `migrations/` — populated only after `supabase migration new <name>` generates approved filenames.
- `functions/` — future server operations, including payment idempotency and approvals.
- `seed/` — fictional test data only, never production students.

## Deployability checkpoints
Review explicit PK/FK, cross-campus containment, RLS+GRANT, auth bootstrap, tenant isolation, safe triggers, privilege escalation, operation IDs. Locally reset and migrate; test RLS with Owner and campus-bound users; run Supabase advisors; deploy only after review.

Draft SQL is not executable evidence. No live school records until end-to-end tests pass.
## D03-T02 documents
The `drafts/DB02_DOCUMENT_STORAGE_PLAN.md` describes future private Storage requirements; `tests/DB02_DOCUMENT_ACCEPTANCE.md` lists tests still to run locally. No Storage bucket, SQL migration, or Edge Function was deployed. The draft now has 10 RLS-enabled public DB02 tables (not 10 live tables).

## Schema-first development policy (2026-11-16)

No Flutter implementation changes or new hosted SQL deployments in this
schema-design workstream. See `../docs/31_SCHEMA_FIRST_ROADMAP.md` for the
nine-domain inventory and counts. DB01/DB02 baseline already live; DB03
is drafted on the separate schema branch. After DB03: **6 core schema
subjects remain to design (DB04–DB09); 7 remain to deploy (DB03–DB09).**

The authored DB03 files are:
- `drafts/DB03_FEES_BILLING_SCHEMA.sql` — 18 table DDL, RLS, campus FKs,
  category-scoped discounts, exact minor-unit money, immutable posted facts.
- `tests/DB03_FEES_SCHEMA_INTEGRATION.sql` — rollback-only fictional SQL
  constraints/permission fixture (NOT EXECUTED).
- `tests/check_db03_fees.py` — static source checker.
- `../docs/32_DB03_FEES_BILLING_DESIGN.md` — domain rules and integration gaps.

No client role has been given finance table access; all posting RPCs and
DB06 account links require a separate local test/review phase.

## DB04 Attendance schema design — STACKED DRAFT, NOT DEPLOYED

- `drafts/DB04_ATTENDANCE_SCHEMA.sql` — 11 campus/year/section-scoped RLS
  tables: attendance calendar, policies, teacher duties, student register,
  immutable initial marks/correction requests/decisions, staff daily
  attendance and immutable staff corrections; 4 integrity functions and
  19 triggers. Depends on DB03 enrollment scoped UNIQUE constraint.
- `tests/DB04_ATTENDANCE_SCHEMA_INTEGRATION.sql` — rollback-only fictional
  campus/section/date/correction/RLS fixture, **not executed**.
- `tests/check_db04_attendance.py` — source structural checks.
- `drafts/DB04_ATTENDANCE_RUNBOOK.md` — local SQL testing and teacher role
  authorization prerequisites.
- `../docs/33_DB04_ATTENDANCE_DESIGN.md` — design contract and known gaps.

**No Flutter code or hosted Supabase changes** were made in DB04 design.
5 of the 9 core domains still need full design (DB05–DB09), while 7
DB03–DB09 domains remain undeployed.

## DB05 employee and payroll schema (source draft only)
- `drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql`: 20 new public RLS-denied HR
  tables including school-wide employee identity, campus/teaching assignments,
  approved versioned salary rates, one school-month payroll assessment,
  partial salary payments, advances, repayment and immutable corrections.
- `tests/DB05_PAYROLL_SCHEMA_INTEGRATION.sql`: fictional rollback-only SQL
  acceptance suite for multi-campus assignment, salary uniqueness,
  partial payments, repayment same-employee FK, money totals and RLS.
- `tests/check_db05_payroll.py`: static structure checker (NOT runtime SQL).
- `drafts/DB05_PAYROLL_RUNBOOK.md`: isolated local test and security gates.
- `../docs/34_DB05_EMPLOYEES_PAYROLL_DESIGN.md`: payroll rules, DB06
  cashbook/DB08 approval boundaries, unresolved authorization and balances.

**No migration has been deployed, no production records created and no
Flutter code changed.** DB05 is stacked on DB04/DB03 designs; use reviewed
migration order after all nine core domains are designed.
**4 full schemas remain to design (DB06–DB09); 7 remain undeployed (DB03–DB09).**
