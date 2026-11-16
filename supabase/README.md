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
