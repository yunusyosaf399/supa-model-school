# Software Requirements Specification — v1.0 draft

## Goal
An integrated multi-campus school management system for Windows Desktop and Android. One designated Windows desktop stores its **assigned campus** offline in SQLite/Drift; all other devices operate online against Supabase PostgreSQL.

## First-release scope (P0)
- School/campus/academic-year foundation, authentication, campus-scoped authorization and owner reporting.
- Student profiles, family/guardians, conditional admissions with document deadlines and optional Principal approval.
- Campus transfers with Owner approval, full history retention and debt-collection responsibility transfer.
- Fee structures by campus/class, student-specific transport, discounts, scheduled charges, partial and advance payments, month-wise arrears and receipts.
- Student/staff attendance, daily P/A/Late/Leave, audit of corrections; Leave non-attended and Late attended.
- Employee profiles, fixed monthly payroll, manual deductions, advances, partial salary payments, salary slips.
- Expenses, cash/bank accounts and daily cash closing; approval thresholds and correction workflow.
- Reliable durable offline sync, idempotency, conflict review, backups, PDF slips and essential reporting.

## Supporting / later scope
P1: basic canteen, uniforms, vehicles, search and keyboard shortcuts, campus financial summary. P2: teacher login, exams/results, parent portal, advanced costing and optional Urdu UI.

## Nonfunctional requirements
- No unauthorized cross-campus access including global search, uploads, reports and offline cache.
- No financial double counting or silent overwriting; append corrective events.
- Exact money representation, safe receipt numbering, audited privileged actions.
- Automatic sync when connectivity resumes, plus Sync Now.
- Reproducible backups and tested restoration; cloud sync is not backup.
- English interface first; localization-ready for Pakistani Urdu.

## Release constraint
21-day **pilot target**, not a production guarantee. The pilot is unacceptable until the financial integrity, RLS, and offline/recovery tests in docs/09_TEST_PLAN.md pass.

Status: requirements agreed in conversation; implementation and verification pending.