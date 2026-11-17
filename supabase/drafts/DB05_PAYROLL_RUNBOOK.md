# DB05 — Local PostgreSQL Payroll Schema Test Runbook

**REVIEW-ONLY DESIGN. Do not deploy to the connected live school.**

## Prerequisite SQL order

Use a disposable local Supabase/PostgreSQL database with Auth schema.
Create fictional local account `sms-adm-admin-a@example.invalid`.

1. DB01 deployed-style foundation + applied Owner academic extensions.
2. DB02 student/guardian/admission baseline.
3. DB03 fee/billing schema draft (PR #25).
4. DB04 attendance schema draft (PR #26).
5. `supabase/drafts/DB05_EMPLOYEES_PAYROLL_SCHEMA.sql`.

The DB05 source is stacked on DB04, so review this full dependency chain
before creating approved migrations. Only after all nine schema designs
are finished should the final migration order be produced with the
locally installed Supabase CLI's verified `--help` commands.

## Schema tests (fictional, rollback only)

```powershell
python supabase/tests/check_db05_payroll.py
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB05_PAYROLL_SCHEMA_INTEGRATION.sql
```

The second command requires the real local PostgreSQL schema. It does
not test production access, authorization/RLS policy decisions or account
posting; it merely asserts structural FKs, unique keys, journal triggers
and direct-client privilege denial. The script uses BEGIN/ROLLBACK.

## Mandatory manual/adversarial tests after domain review

1. **Campus and school scope:** employee assigned to A and B; wrong-school
   position/assignment, login identity and teacher class assignment must
   fail. Non-primary assignments must not generate duplicate salary.
2. **Effective dates:** employment start/end, expired salary rate, primary
   assignment date overlap, partial FTE shares, teacher class validity,
   salary structures spanning months or two campuses. All are currently
   future trusted transaction checks.
3. **Monthly payroll uniqueness:** two concurrent transactions attempting
   original April payroll for same employee in different campuses must
   produce exactly one accepted payroll entry, even if different UUIDs.
4. **Component computation:** salary line catalog kind must match; gross
   and deductions must reconcile to lines and original approved rate.
   Test daily/hourly, sick/leave and non-working days carefully.
5. **Advance recovery:** two concurrent recovery requests cannot exceed
   the original advance; sum of recovered amounts on the employee/month
   must match the advance recovery snapshot, without extra salary expense.
6. **Partial salary payment:** two legitimate partial payments survive;
   two racing payments must not overpay net salary plus adjustments; a lost
   receipt acknowledgment with unchanged UUID returns exactly one result.
7. **Cashbook integration:** DB06 will record exactly one offsetting
   cash/bank account movement for each salary disbursement or advance.
   Reversing a bank payment must not erase the original record.
8. **Closing:** a closed payroll month is immutable; an approved correction
   in later month creates an adjustment, not an edited prior payroll.
9. **Leave/attendance:** only approved leave days count, once per
   employee/date across campuses; wrong user/staff mapping and
   unapproved attendance correction cannot change earned salary.
10. **Privacy/security:** test anon, regular authenticated employee,
    teacher, HR, Accountant, campus Principal, school Owner with two
    campuses. Ordinary account cannot list school salaries or change
    salary rates. Deny cross-campus personnel data. Never trust
    user-editable Auth metadata for salary authorization.
11. **Offline:** request requiring approval remains local pending while
    disconnected; only online approval+posting can issue a final salary
    receipt, bank movement or salary advance recovery.
12. **Reporting:** payslip, salary outstanding, advances and multi-campus
    cost-center figures derived from immutable posted entries. No
    double-count of payroll due to assignment or salary advance payout.

## Explicit status

SQL authored and statically inspectable in GitHub only. PostgreSQL
parser/execution, complete RLS/permissions tests, payroll/DB06 service
operations, real device-sync work, encryption and production deployment
have **NOT RUN** or are **NOT IMPLEMENTED**.

**Remaining schema designs after DB05: 4 (DB06–DB09).
Domains waiting for deployment: 7 (DB03–DB09).**
