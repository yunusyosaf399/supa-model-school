# DB04 — Student and Staff Attendance Schema Design

**Date:** 2026-11-16  
**Status:** SQL DESIGN DRAFT only. No Flutter code; not deployed.  
**Branch:** `db/db04-attendance-schema-20261116` stacked on DB03 draft PR #25  
**Schema:** `supabase/drafts/DB04_ATTENDANCE_SCHEMA.sql`

## Core domain behavior

- Single school with multiple campuses. A pupil's attendance must be tied to
  the actual campus, academic year, class, optional section and valid active
  or historical enrollment on that date; a UI campus filter is insufficient.
- A **daily first-period session** is the canonical student day attendance.
  A separate **after-break session** is optionally enabled by active campus
  policy. After-break records must not double-count a pupil's school day.
- One primary teacher duty per campus/class/section/date/session, with at
  most one separately approved substitute. The future posting operation
  must verify the currently signed-in user owns the selected duty and holds
  an active campus/subject/class assignment; the school Owner cannot secretly
  impersonate a classroom teacher.
- Teacher assignments are day/session-scoped; `attendance_duties` makes
  substitutes explicit and auditable. Schedule generation and full
  subject/timetable assignment are future cross-domain work.
- A campus calendar differentiates instructional/exam days from closures,
  weekends and holidays. Student registers are blocked on non-instructional
  days. Staff may be recorded as working on a holiday/offsite.
- Attendance statuses: `present`, `absent`, `late`, `excused`, `leave`,
  `sick`. School policies define how these appear in official reports;
  suggested daily numerator is present+late (late additionally reported
  separately), not present+late+leave automatically. Every report must
  distinguish scheduled school days from unmarked/missing attendance.
- Repeated submission of an operation ID must not double-create registers,
  marks or correction decisions. Daily register uniqueness, event UUIDs,
  and server-side idempotency transactions enforce this after deployment.
- Student attendance records are **historical facts**. Corrections create
  request and decision rows, never edit the initial mark.
- Staff attendance is tied to an actual `user_profiles` account in v1.
  DB05 will link employees, effective dated staff campus assignments, pay
  periods, leave and salary rules. Staff attendance never independently
  triggers pay or expense posting.
- Campus transfers preserve historical marks at the old campus; the new
  campus uses the student's new enrollment. No reassignment of old marks.

## Tables — 11 new public tables

| Table | Purpose |
| --- | --- |
| `school_calendar_days` | Per-campus academic-year instructional, exam, weekend, holiday, closure dates |
| `attendance_policies` | Versioned per-campus/year first-period and optional after-break settings |
| `attendance_duties` | One day/session/class/section primary duty and approved substitute |
| `attendance_registers` | Scoped attendance session identity and draft/submitted/locked lifecycle |
| `attendance_register_events` | Immutable action UUIDs and registration lifecycle audit |
| `student_attendance_marks` | Append-only original initial student marks from correct enrollment |
| `attendance_correction_requests` | Proposed mark changes with reason and expected revision |
| `attendance_correction_decisions` | Immutable approved/rejected decision with scoped status and revision |
| `staff_attendance_records` | Daily staff status/check-in/out, independently of DB05 payroll |
| `staff_attendance_correction_requests` | Staff attendance correction request, prior revision and reason |
| `staff_attendance_correction_decisions` | Immutable decision/approved correction for staff attendance |

## Database integrity

- All 11 tables have explicit **RLS enable** and all direct grants to
  `anon` and `authenticated` are revoked. No client SELECT/INSERT/UPDATE
  or permissive policy is created here.
- Student enrollment's composite scope uses the 6-column
  `db03_enrollment_finance_scope_unique` constraint that is introduced
  by DB03. Therefore DB04 SQL is a **stacked dependent draft**, not a
  standalone migration against live DB02.
- Calendar school/campus/year FK, year-bounds trigger, register calendar FK,
  teacher duty FK, register year/class/section FK and student enrollment
  FK prevent unaudited cross-campus/class/year references.
- The mark trigger checks **section equality**, student's enrollment date
  range, register draft state and the authorized selected duty's teacher.
  The register trigger checks the active policy and blocks disabled
  after-break attendance, holiday/closure registers and invalid lifecycle
  transitions or locked/unversioned edits.
- Each class/section/session/date register and primary duty is unique with
  `UNIQUE NULLS NOT DISTINCT`, including sectionless classes.
- 8 append-only table guards reject UPDATE/DELETE and 8 more triggers
  reject TRUNCATE. Original marks, both correction stages, staff marks,
  duty assignments and register action events are preserved.
- Approved correction status must equal the requested status via a
  composite FK. Correction requests have one decision and operation UUIDs
  are unique per school. Revision sequence, permission and complete-class
  roster checks still require authorized server transactions.

## Attendance authorization: explicitly unfinished

The **currently deployed** DB01 role whitelist includes only
`owner`, `super_admin`, `principal`, `admin`, `accountant` and
`attendance_staff`. It does NOT yet include a `teacher` role (or the
expanded HR role catalog agreed for the complete application).

Thus `assigned_user_id` references an actual Auth identity but a FK
alone does not confirm a teacher may mark this class. Before exposing an
attendance API, expand/review DB01 roles, campus class/section/subject
assignments, substitute approvals and per-operation permissions. Record
and validate current role/assignment in trusted SQL or Edge functions.
A school-wide Owner can review records where authorized, but the ordinary
first-period submit must be attributed to the scheduled teacher or approved
substitute. Never grant `authenticated` unrestricted access or authorize
using editable user_metadata.

### Planned server-only operations, NOT implemented by this task

1. Configure campus/year calendar and active attendance policy.
2. Schedule first-period duty, after-break duty and approved substitute.
3. Save a register and *all scheduled students' initial marks* in one
   authenticated, idempotent transaction; reject missing roster marks and
   disallowed backdating. The first-period assigned teacher is responsible.
4. Submit/lock/reopen via validated status transition and simultaneous
   immutable register event (never mark as submitted before complete).
5. Request/approve/reject a correction only with a reason and current
   effective revision, maintaining exactly one next approved revision.
6. Record staff attendance subject to DB05 employee assignment;
   correction decisions must not rewrite a closed payroll period.
7. Return authorized campus/year/section/date reports; daily present
   counts must not multiply by optional after-break registers.
8. Accept assigned-campus Windows offline *draft requests* only after
   secure device authorization, encryption and online server acceptance.
   Android attendance is online-only in pilot.

## Tests and remaining gates

- `supabase/tests/DB04_ATTENDANCE_SCHEMA_INTEGRATION.sql` — fictional,
  transactionally rolled-back schema/RLS fixture:
  calendar year bounds, one active policy, unique primary duty and register,
  disabled after-break, holiday register, same-section enrollment,
  cross-campus attempt, immutable marks, illegal state regression, approved
  correction FK and staff correction, private table access and TRUNCATE.
- `supabase/tests/check_db04_attendance.py` — static schema guard.
- **NOT EXECUTED**: PostgreSQL DDL, real RLS tests, teacher-specific
  authorization, multi-session idempotency, DST/date edge tests, concurrency
  for correction revisions, schedule validity, staff/payroll authorization
  and actual cloud/offline integration.

## Schema-first plan and counts

Nine core domains DB01–DB09: DB01 and DB02 are baseline deployed; DB03 and
DB04 are authored as SQL drafts on stacked branches (neither deployed).
**Five full domains remain to design: DB05, DB06, DB07, DB08 and DB09.**
**Seven domains remain undeployed: DB03–DB09.** This counts domain designs,
not the larger 114-item Flutter/project backlog.

**Next full domain: DB05 Employees, Assignments, Payroll and Advances.**
