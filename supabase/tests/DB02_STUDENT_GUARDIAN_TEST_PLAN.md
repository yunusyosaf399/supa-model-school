# D03-T01 — Students and Guardians Acceptance Matrix

**Status: DRAFT review checklist.** The DB02 SQL has NOT been run or deployed.

## Entity integrity
- Student has a stable UUID and a school-unique permanent registration number.
- The school registration index rejects case-only duplicates (SMS-001 and sms-001).
- Student identity is school-wide, independent of current campus and academic year.
- Guardians are school-scoped contact records reusable for several siblings at different campuses **within the same school**.
- student_guardians links both student and guardian through their (id, school_id) composite foreign keys.
- A school-A student cannot link to a school-B guardian, even through a fabricated junction row.
- A student may have father, mother, and guardian links. Multiple guardian/other links are permitted.
- Only one primary guardian/contact can exist for the same student at a time.
- Duplicate father or mother link for one student must fail.
- A guardian may remain linked to several siblings even when one student transfers campuses.
- Registration and roll numbering are separate business objects: DB02 does not allocate numbers from an untrusted client.

## Security
- Every DB02 public table has RLS enabled.
- The first draft does not expose DB02 data to `anon` or `authenticated`, even if a user logs in.
- Do not grant full student or guardian table SELECT to an entire campus until field-level PII authorization has been reviewed.
- Parent/guardian phone, address, government ID and uploaded documents need restricted views or server-backed operations.
- No direct INSERT/UPDATE/DELETE; use trusted, audited app operations after DB01 authorization is verified.

## Test cases to implement on local Supabase
1. Insert two schools, campus A/B per school, two students and their guardians under trusted test administrator.
2. Duplicate exact and case-only school registration number → unique violation.
3. Another student in another school may use same human-readable registration number → accepted.
4. Same guardian linked to two sibling students in same school → accepted.
5. Student in School A linked to guardian in School B → FK violation.
6. Attempt a second primary guardian for same student → unique violation.
7. Attempt a duplicate father or mother relationship for one student → unique violation.
8. Plain authenticated/anonymous SQL/API access to students/guardians → denied.
9. Deleted or changed student's active campus does not modify identity/guardian history.
10. DB01/DB02 run in correct dependency order; enrollments preserve campus history.

## Completion boundary
**D03-T01** means schema **authored, reviewed and static checks passed**.
Actual migration execution, authenticated RLS testing and live deployment remain separate pending work; DO NOT claim these tests have run.
