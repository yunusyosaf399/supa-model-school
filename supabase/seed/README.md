# Supa Model School — optional fictional seed data

Files in this folder are **not** automatic production migrations. Never run all seed files on a real school's live data without reviewing their scope.

## Staff, student transport, and attendance foundations (18 November 2026)

- `20261118_fictional_staff_transport_attendance.sql`: idempotent insert-only fixture for the **existing** Supa Model School / Main Campus / academic year 2026–2027. Requires 33 pre-existing `SAMPLE-2026-*` students. It does not add students or rewrite any existing school, admission, attendance, fee, expense, payroll, or authentication records.
- `../tests/20261118_sample_staff_transport_attendance_integrity.sql`: read-only integrity test for the fixture.

Fixture contents: 5 departments, 8 positions, 11 fictional employee profiles, 11 campus assignments, 2 buses, 2 routes, 4 stops, 12 eligible existing students on routes, 3 explicitly marked **SAMPLE** school-calendar days, and one **draft** attendance policy.

**Important limits:** The employee names and bus registrations are fictional; `employees.auth_user_id` is intentionally null. They cannot log in. No Teacher login account is created. No payroll, payslip, fee charge, payment, or bank movement is posted. No attendance registers or permanent attendance marks are invented, because a verified teacher assignment and active policy are required by DB04. This seed does not bypass student document requirements or Principal admission approval.

To run on a test database, open the seed SQL in Supabase SQL Editor after confirming the school, campus, year and 33 sample student registrations match. The script is scoped, transactional, and safe to rerun; a mismatch raises an exception. Run the matching read-only integrity test afterward.

**For later cleanup:** All new employee numbers and department/position codes use `SAMPLE` prefixes. Routes and vehicles also use `SAMPLE` prefixes. Cleanup must be planned in dependency order—transport student assignments before stops and routes, employee assignments before employees and positions, and school-calendar days only after checking references. Do **not** broadly truncate school tables or delete financial evidence. Do not clean current sample data until the owner explicitly requests it and the live relational dependencies have been checked.

## Other seeds

- `20261116_dashboard_demo_only.sql`: legacy demo-dashboard fixture, with strict empty-school guards; do **not** use on a populated school.
- `20261118_handwritten_financial_categories.sql`: optional category template only, with an explicit finance review requirement; it never posts money.
