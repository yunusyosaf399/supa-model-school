# Supa Model School — Schema-First Roadmap (DB01–DB09)

**As of 2026-11-16.** This is the canonical COUNT of major schema
domains; the separate 114-task tracker includes UI/tests and MUST NOT be
mistaken for the number of schemas.

## Nonnegotiable development order

1. Finish **all nine core schema domain designs** first.
2. Inspect campus isolation, student history, permissions, RLS, PK/FK,
   financial integrity, offline rights and cross-domain dependencies.
3. Only after schema design/acceptance is complete, test each migration in a
   disposable local Supabase/PostgreSQL environment using fictional data.
4. Resolve dependency order, produce and review real CLI-named migrations.
5. Deploy remaining schema migrations in approved order, then work on
   server operations and Flutter integration. **No Flutter coding in this
   schema-design conversation.** Existing Flutter/UI code may be inspected
   for requirements, but must not be changed here.

## Nine core database domains

| ID | Domain | Schema design status | Hosted deployment | Significant remaining work |
| --- | --- | --- | --- | --- |
| DB01 | School foundation, Auth roles, campuses, academic years/classes | Baseline authored + deployed | Deployed | Expand complete role catalog, user access, tests/review |
| DB02 | Students, admissions, guardians, enrollments, documents | Baseline authored + deployed | Deployed | Full document upload/verification service and acceptance testing |
| DB03 | Fee plans, discounts, charges, partial receipts, credit, bank claims | **18-table SQL design in draft PR (2026-11-16)** | NOT deployed | Test SQL; design atomic server posting, DB06 account links |
| DB04 | Student/staff attendance, school calendar and corrections | NOT fully designed | NOT deployed | Full schema design next |
| DB05 | Employees, assignments, payroll, salary advances/repayments | NOT fully designed | NOT deployed | Full schema design |
| DB06 | Financial accounts, cash/bank, expenses, transfers and closings | NOT fully designed | NOT deployed | Full schema design (complements DB03) |
| DB07 | Canteen, uniforms, inventory, transport/vehicles | NOT fully designed | NOT deployed | Full schema design |
| DB08 | Approvals, audit, correction workflows, templates, notifications | NOT fully designed | NOT deployed | Full schema design |
| DB09 | Offline sync, device receipts/cursor, backups and reporting projections | PARTIAL drafts exist, full design incomplete | Dashboard demo/read-only portion deployed; sync NOT deployed | Complete unified device sync, backups and status schema |

Naming caveat: existing `DB05_UI_PREFERENCES.sql` is a small auxiliary
preferences draft and NOT the DB05 payroll domain; the existing
`DB09_OWNER_DASHBOARD_READ_PROJECTION.sql` is a read-only dashboard
projection and NOT a complete DB09 sync/backup architecture.

## Remaining-count rule for EACH response

- **Baseline deployed:** 2 of 9 domains (DB01, DB02).
  DB01/DB02 operational workflows still have unresolved gaps.
- **New design authored but not deployed:** 1 of 9 (DB03).
- **Full-domain designs remaining after DB03:** **6** (DB04–DB09).
  DB09 has preliminary server-sync code but not a finished domain.
- **Core domains still requiring deployment:** **7** (DB03–DB09).
  Previously deployed DB01/DB02 are not rolled back.

Before DB03 source design was started: 7 full-domain designs remained.
After DB03 source design is reviewed: 6 remain. Counts are **domains**,
not SQL files, tables, Flutter screens or total project tasks.

## Cross-domain dependency decisions

- Single school with multiple campuses; class/section and student data
  must use the same campus and academic-year FK constraints.
- Source of truth for school currency is `public.schools.currency_code`;
  DB03/DB06 financial postings must use integer minor units or exact NUMERIC.
- A scholarship can affect tuition only, transport only, or specified other
  categories, never silently everything.
- DB03 student debt, receipt and credit journals are different from DB06
  cash/bank money movement; one verified receipt must commit the matching
  account movement atomically in the future server posting layer.
- Original campus billing debt stays immutable on a campus transfer;
  reassigned collection responsibility is auditable, not a duplicate charge.
- DB08 approval-requiring entries remain pending offline; no local-only
  authorization can post cash/expenses or issue globally final receipt IDs.
- DB09 assigned Windows PC stores only its authorized campus replica,
  and must apply server changes/cursor atomically after verification.
  Android remains online-only in the pilot.
- Uploaded payment/admission documents must use private storage and
  documented authorization. Uploading a bank slip is not verification.

## Current UI relevance (read-only inspection)

Latest merged main UI includes responsive login/Owner setup, Owner academic
structure, admission wizard with fee preferences, student views and an
Owner dashboard with example fee collection/dues. DB03 fee panels must
not claim real collections before DB03+DB06 posted financial transactions
and authorized dashboard projections exist.

**Next domain to author: DB04 Attendance.**
