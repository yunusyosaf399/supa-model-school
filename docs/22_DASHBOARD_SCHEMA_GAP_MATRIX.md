# Dashboard / login schema coverage and gaps

Updated 2026-11-16. Source inspection only; hosted school-domain tables are NOT deployed.

| Screen capability | Existing source | Addition / gap | Implementation rule |
| --- | --- | --- | --- |
| School and campus | DB01 `schools`, `campuses` | None | Show only after authorized account context, or local known values on trusted device |
| Auth credentials | Supabase `auth.users`, DB01 `user_profiles` | Real Auth integration not implemented | Authenticate first, then load authorized campus choices; never store passwords in school tables |
| Username sign-in | No alias table / trusted resolver | Needs design + anti-enumeration controls | Do not map username to email by unauthenticated table lookup |
| Roles / authorization | DB01 `user_roles`, `role_permissions`, private helpers | DB01 currently contains only owner, super_admin, principal, admin, accountant, attendance_staff | Before real login add full agreed role catalog, assignment scope, parent/family isolation and negative RLS tests |
| Academic year | DB01 `academic_years` | No new table | Select authorized active year and retain historical year navigation |
| Theme / shortcut preferences | No stored row model | `DB05_UI_PREFERENCES.sql` DRAFT | Own-only RLS, authorized preferred campus, no direct role grants |
| Active student count | DB02 `students`, `student_enrollments` | No trusted aggregate/RPC yet | Count campus+academic-year enrollments, avoid duplicates |
| Recent admissions | DB02 `admission_applications` and `students` | No dashboard authorized query | Count finalized students only; never expose other campus/student PII |
| Fee collected / outstanding | Not in DB01 / DB02 | Fee assessment, category, discount, receipt, partial payment, reversal, immutable ledger, reporting | Design finance source first; monetary units integers/decimal, no floating points |
| Fee trend | No finance source yet | Campus and timezone-aware monthly aggregation | Read-only authenticated and scope-checked reporting endpoint |
| Today attendance | No canonical register in DB01 / DB02 | Attendance session, class+section assignment, mark, capture adapter, history | Session+date/term based data and authorized teacher/campus scope |
| Approval queue | Admission draft + workflow schema exists | Separate expense/leave/transfer approvals not all designed | Permission + action + campus scope; no offline final approvals |
| Notifications | No verified inbox projection | Notifications, delivery state, recipient isolation and read timestamp | Owner/admin privileges never bypass recipient read restrictions |
| Sync status | Drift/outbox drafts, device registration and sync SQL draft | No proven end-to-end encrypted sync | Display last acknowledged server cursor only; never show a fake 'In Sync' |
| Backup | Owner-configured destinations planned | Backup manifest, checked restore point, recovery log | Display actual verified backup only |
| Global search | Student preview local filter only | Authorized search RPC/indexes for other modules | Filter in data source using RLS, not merely Flutter search boxes |

## Domain dependencies
Before connecting dashboard counters:
1. Finish DB01 RLS execution, Auth bootstrap, active profile and full role/action/scope model.
2. Validate DB02 admissions transaction and documents.
3. Implement durable finance and attendance source models with negative authorization tests.
4. Implement server-side dashboard aggregates and scoped search.
5. Implement independently verifiable sync and backup status.
6. Replace all demo sample values with immutable authorized projections. Keep true dark/light appearance available without adding any RLS bypass.

**Do not deploy `DB05_UI_PREFERENCES.sql` by itself** before the DB01 prerequisite, migrations, and local RLS tests.
