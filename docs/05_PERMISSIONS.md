# Roles, RLS and campus scope

- Owner/Super Admin: school-wide controls and all campuses.
- Principal: assigned campuses + consolidated summaries; detailed cross-campus reports only by explicit Owner grant.
- Admin: student/admission/fee operations, corrections requested not silently applied.
- Accountant: permitted fees/payments/payroll/cashbook.
- Attendance Staff: today-only attendance submission and campus-scoped reports.
- Teacher: employee record without login in pilot.

Offline desktop stores only assigned campus. Backend must enforce per-row/operation permissions even where Flutter hides UI. Approval for campus transfer and financial corrections is Owner-only. Payroll/expense approval role may be Owner-configured.

`user_roles` must NEVER be writable by an ordinary authenticated session. Do not use user-editable JWT metadata for authorization. RLS tests need Owner, Principal, Admin, Accountant and Attendance Staff on two campuses.

DB01 draft enables RLS and read-only baseline; no direct client mutations until dedicated validated operations exist. DB02 defaults to deny until complete student-access policies are reviewed.
## DB08 approval/role source design (2026-11-17)
DB08 draft extends DB01 `user_roles` whitelist with Vice Principal,
HR, Teacher, Coordinator, Librarian, Transport Manager, Driver, Nurse,
Store Keeper, Security Guard and Parent. The source is **not deployed**;
Teacher may exist without Auth login in the pilot, but when login is
assigned, DB05 employee/campus mapping and current permissions must be
validated before teacher attendance posting. Owner/Super Admin remain
school-wide and other roles campus-assigned.

Roles never automatically grant table access. DB08 defines versioned
approval rules and typed request sources, grants and audit, but trusted
campus authorization/RLS and actual decision/posting services remain TODO.
See docs/37_DB08_APPROVALS_PERMISSIONS_DESIGN.md.
