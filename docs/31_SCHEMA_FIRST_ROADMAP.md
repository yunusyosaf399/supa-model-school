# Supa Model School — Schema-First Roadmap (DB01–DB09)

**Current verified deployment 2026-11-17.** This is the canonical COUNT of major schema
domains; the separate 114-task tracker includes UI/tests and MUST NOT be
mistaken for the number of schemas.


## Latest deployment verification (2026-11-17)

All nine DB01–DB09 **SQL schemas have now been deployed**. GitHub Actions [seven-domain local acceptance](https://github.com/yunusyosaf399/supa-model-school/actions/runs/44031312887) passed, and the [versioned migration PR check](https://github.com/yunusyosaf399/supa-model-school/actions/runs/44032342791) passed before [PR #34 merged](https://github.com/yunusyosaf399/supa-model-school/pull/34). New live migration versions are 20261117062924, 20261117062944, 20261117063002, 20261117063034, 20261117063050, 20261117063105 and 20261117063123. Current hosted project: **169 public tables, 169 RLS-enabled, 14 migration history entries**; one existing school, campus and role retained. **0 SQL domain schemas await deployment.**

This does **not** mean the application is ready for live data entry. Security-granted authenticated read/write workflows, fee/payroll accounting posting, DB07 COGS, DB08 approvals, DB09 real offline synchronization and encryption/backups, two-session concurrency and privacy/restore drills are still unfinished. Some archival sections below reflect the *predeployment design stage*.

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
| DB03 | Fee plans, discounts, charges, partial receipts, credit, bank claims | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Implement fee charge/discount/receipt authorization, exact accounting posting and concurrent over-allocation prevention; add role-based RLS |
| DB04 | Student/staff attendance, school calendar, teacher duties and corrections | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Implement teacher duties and current-campus attendance submission/correction authorization, class assignments and RLS integration |
| DB05 | Employees, multi-campus assignments, teaching duties, leave, salary and advance recovery | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Implement payroll privacy/approval, salary payment and advance recovery concurrency; link DB06 accounting |
| DB06 | Ledger accounts, double-entry cash/bank, expenses, transfers, capital, closing and reconciliation | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Implement trusted financial posting, matched fee/payroll/DB07 retail and COGS sources, balance/closed-period concurrency |
| DB07 | Inventory, canteen, uniforms, production, transport, vehicles and maintenance | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Implement no-negative-stock, approved sales/transfers, driver eligibility and matching DB06 inventory/COGS journals |
| DB08 | Expanded role catalog, campus permissions, approvals, audit, templates and notifications | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Implement trusted multi-step approval engine, role/permission grants and current actor/campus RLS verification |
| DB09 | Windows campus-only offline sync, cloud change feed, conflict receipts, encrypted backup/restore, reporting | **SQL schema deployed 2026-11-17** | **Deployed (schema only)** | Reconcile legacy D04 offline drafts; implement authenticated sync APIs, SQLite encryption, backup/restore and multi-device concurrency |

Naming caveat: existing `DB05_UI_PREFERENCES.sql` is a small auxiliary
preferences draft and NOT the DB05 payroll domain; the existing
`DB09_OWNER_DASHBOARD_READ_PROJECTION.sql` is a read-only dashboard
projection and NOT a complete DB09 sync/backup architecture.

## Remaining-count rule for EACH response

- **Deployed SQL schema domains:** 9 of 9 (DB01–DB09).
  DB01/DB02 operational workflows still have unresolved gaps.
- **New schema domains deployed on 2026-11-17:** 7 of 9 (DB03–DB09); business services/role policies are not complete.
- **Full-domain designs remaining after DB09:** **0**. All 9 core domains have source design; this does NOT mean the migrations or runtime are approved.
- **Core domains still requiring initial SQL schema deployment:** **0**. All DB01–DB09 SQL deployed; server operations and stronger role-based security tests remain.

Before DB03 source design was started: 7 full-domain designs remained.
After DB03 source design is reviewed: 6 remain; after DB04: 5 remain; after DB05: 4 remain; after DB06: 3 remain; after DB07: 2 remain; after DB08: 1 remains; after DB09: 0 remain. Counts are **domains**,
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

**Next stage: cross-domain integration review, PostgreSQL/RLS/concurrency testing and approved migrations; NO Flutter code in this workstream.**

## DB04 attendance schema, 2026-11-16
11 RLS-denied tables designed on stacked draft DB04 branch, including
campus calendar, teacher first-period/optional after-break duties, class/
section register, original student marks and immutable student/staff
correction requests and decisions. No Flutter code or hosted SQL changes.
See docs/33_DB04_ATTENDANCE_DESIGN.md. **5 full domain designs remain; 7
remain undeployed.** Actual PostgreSQL fixture/RLS has not yet run.

## DB05 employee/payroll schema source (2026-11-16)
20 RLS-denied public tables cover employee identity, effective-dated
multi-campus assignments, school-year teaching assignments, leave, salary
structure/rates, school-wide monthly payroll, signed adjustments, advance
loans/recoveries, partial payments, reversals and immutable operation
receipts. Original salary assessment is unique per (school,employee,month).
Source in `supabase/drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql` and `docs/34_DB05_EMPLOYEES_PAYROLL_DESIGN.md`.
No hosted database or Flutter changes. **4 full domains remain to design
(DB06–DB09), and 7 domains remain undeployed (DB03–DB09).**

## DB06 finance/cashbook schema source (2026-11-16)
20 deny-by-default RLS tables designed in stacked draft branch. Uses a
school-wide chart of accounts, per-campus physical cash/bank accounts,
source-linked immutable double-entry journals with commit-time balancing,
DB03 fee and DB05 payroll accruals, pending/approved expenses, capital,
cross-campus transfers, cash counts/closings and bank reconciliation.
See `docs/35_DB06_FINANCE_CASHBOOK_DESIGN.md` and
`supabase/drafts/DB06_FINANCE_CASHBOOK_SCHEMA.sql`. No Flutter code or new
live SQL deployed. **3 full schema designs remain (DB07–DB09), while 7
remain undeployed (DB03–DB09).**

## DB07 inventory, retail, uniforms and transport source (2026-11-16)
Designed **37 new deny-by-default RLS tables**, including campus stores,
items/lots, procurement orders/receipts, signed append-only stock movements,
typed sources, cross-campus transfers and counts, canteen prices/sales,
uniform BOM/production/sales, student route assignments, DB05 drivers,
trip/maintenance history, DB06 expense links and sale reversals.
Two deferred sale-total and stock-source integrity checks are included.
See `docs/36_DB07_BUSINESS_TRANSPORT_DESIGN.md` and
`supabase/drafts/DB07_INVENTORY_CANTEEN_UNIFORM_TRANSPORT_SCHEMA.sql`.
DB06 needs a **reviewed journal kind/source extension** for actual canteen,
uniform, inventory and COGS posting before any migration is prepared.
No Flutter or hosted Supabase SQL deployment occurred. **2 full domains
remain to design (DB08–DB09); 7 domains remain undeployed (DB03–DB09).**

## DB08 approval/role/audit source (2026-11-17)
Designed 18 deny-by-default RLS tables, expanding DB01 school/campus role
whitelist to school Owner, teachers, transport, Store Keeper, parents etc.
Per-school role permission mapping, expiry-bound overrides, policy versions,
sequential reviewer steps, typed approval source references, no-self-review
trigger, immutable decisions/audit, document templates, notifications and
operation receipts. No live role/policy or RPC changes. See
`docs/37_DB08_APPROVALS_PERMISSIONS_DESIGN.md`.
**1 full domain remains to design (DB09); 7 remain undeployed (DB03–DB09).**

## DB09 sync, backup/restore and reporting schema source (2026-11-17)
18 deny-by-default RLS public tables designed for assigned-campus Windows
devices, revocation, per-operation SHA256 receipts, row-locked commit-order
change feed, tombstones, durable cursor claims, conflicts/resolutions, Owner
configurable encrypted backup destinations, manifests, restore checks and
scoped real/demo reporting. Android is online-only in v1. Earlier unmerged
D04-T03/T04 ingest/change-feed drafts must be consolidated, not duplicated.
See `docs/38_DB09_SYNC_BACKUP_REPORTING_DESIGN.md`.
**0 full schema domains left undesigned. 7 DB03–DB09 domains require local
acceptance, migration reconciliation and deployment** (DB09's earlier demo
read-only portion is not its core sync implementation).
