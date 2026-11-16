# DB04 Attendance — Schema/RLS Acceptance Runbook (LOCAL ONLY)

**No Flutter code changes or hosted Supabase migrations in this task.**

## Dependency order and current state

The DB04 draft is stacked on DB03 PR #25. The actual connected hosted
Supabase project has DB01/DB02 baselines deployed, but **neither DB03 nor
DB04 is deployed**. The DB03 draft adds the required composite school/
campus/year/class enrollment UNIQUE constraint; don't apply DB04 alone.

Run in an isolated test Supabase/PostgreSQL instance, **not hosted school**.
Create the fictional user `sms-adm-admin-a@example.invalid` in local Auth
first. Follow current installed Supabase CLI `--help`, prepare reviewed
migrations after every domain design, and preserve current live migration
history. Do not run draft scripts blindly on production.

1. DB01 foundation (plus owner/academic structure migrations).
2. DB02 admissions tables.
3. DB03 fee schema draft, for the enrollment scoped UNIQUE constraint.
4. `supabase/drafts/DB04_ATTENDANCE_SCHEMA.sql`.
5. `python supabase/tests/check_db04_attendance.py` (source-level only).
6. `psql -X -v ON_ERROR_STOP=1 -f
   supabase/tests/DB04_ATTENDANCE_SCHEMA_INTEGRATION.sql`.
7. Verify no direct table SELECT/INSERT/UPDATE/DELETE for anon or
   authenticated (test all 11 tables) and verify current campus role
   restrictions on future operations.
8. Review PostgreSQL SQL parser warnings, FKs, triggers and Supabase advisors.

The SQL fixture uses only fictional identities and BEGIN/ROLLBACK. An
isolated database is still required; a rollback does not magically
make running arbitrary DDL on production safe.

## Essential additional tests before acceptance

- Two campuses with distinct academic years, classes and sections: no
  teacher or attendance_staff can view or submit another campus's marks.
- First-period class duty maps exactly to campus/date/section. Substitute
  must be separately approved; an unauthorized substitute cannot submit.
- School local timezone and school calendar define "today"; holiday,
  weekends, DST transitions and end-of-year boundaries must be tested.
- Optional after-break session disabled/enabled for each campus, and no
  double-counting of pupils in daily attendance percentage.
- Repeated identical register submission operation ID must return same
  accepted receipt; changed payload under same UUID must be rejected.
- Complete roster enforcement: no submitted register with missing pupil
  marks and no marks for unenrolled/transferred pupils.
- Multiple competing correction requests, one immutable decision per
  request; no stale revision acceptance and no unauthorized backdated
  approval. Corrections must never mutate original marks.
- Register lifecycle event and status transition must be committed in
  the SAME transaction, including revision check and approval audit.
- Staff attendance must link to active employee/campus assignment when
  DB05 is designed; approved leave must not cause double payroll counts.
- Offline Windows campus queue remains local/pending until secure server
  confirmation; never mark it submitted merely because an SQLite write
  succeeds. Android remains online only.
- Verify that a user with `attendance_staff` but not actual teacher duty
  cannot submit another class's attendance. Expand DB01 roles before
  enabling teacher portal; the current role enum has no teacher role.
- Verify no student/teacher/staff data leaks through generic dashboard
  aggregate, search or unscoped Supabase RPC.

**Schema-source authorship is complete but runtime/authorization
verification is outstanding.** Do not merge/deploy as production-ready
or enable real attendance records until every acceptance gate passes.

## Progress

2 baseline-deployed domains (DB01/DB02), two nondeployed SQL designs
(DB03/DB04); **five domains remain to design (DB05–DB09)** and **seven
domains still need deployment (DB03–DB09)**.
