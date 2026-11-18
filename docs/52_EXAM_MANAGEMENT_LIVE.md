# Examinations & Tests — Supa Model School live v1

**Implemented 18 November 2026** for the existing one-school/multi-campus Supabase project.

## What works

- Owner → Examinations: authenticated subject creation for an existing class and academic year; creation of **exams, class tests or quizzes** with a class/optional section, subject, date, total and passing marks.
- Owner, and a Principal or staff member with explicit Owner-granted `exams.read`, can see authorized campus exams in a date-sheet-style list and open the eligible student roster.
- The Owner or a staff member granted `exams.update` can enter student marks or mark absence, individually save, and publish completed results. Published results cannot be silently edited.
- **Teacher result access is deliberately blocked** in this v1 until class-and-subject teaching assignments can be enforced in the exam RPCs. Owner and explicitly permitted non-teacher staff (including Principal) work now.
- Student names and registration numbers are read **only through a private, guarded RPC**, not direct RLS table access. The roster is joined to the original enrollment year, class and section.
- Student transfer/withdrawal after the exam **does not erase historical eligibility/results**; validity at the assessment date controls roster inclusion.

## Applied migrations

- `supabase/migrations/20261118094602_db20_exams_tests_schema.sql`: `sms_exam_subjects`, `sms_exams`, `sms_exam_marks`, `app_private.sms_exam_events`, scoped foreign keys, indexes and default-deny RLS.
- `supabase/migrations/20261118094704_db21_exam_rpc_permissions_results.sql`: private authorization and six public wrappers:
  - `sms_exam_snapshot(p_school,p_campus,p_year)`
  - `sms_exam_create_subject(p_school,p_campus,p_year,p_class,p_name)`
  - `sms_exam_create(p_school,p_campus,p_year,p_class,p_section,p_subject,p_kind,p_title,p_date,p_max,p_pass)`
  - `sms_exam_roster(p_exam)`
  - `sms_exam_save_mark(p_exam,p_enrollment,p_score,p_absent)`
  - `sms_exam_publish(p_exam)`
- `supabase/migrations/20261118095758_db22_exam_historical_roster_eligibility.sql`: retains class/section eligibility based on historical enrollment dates, not today's active student status.

These exact migration versions were applied to project `uebzvfzpbqqttbqyxxos`; they are mirrored in GitHub for repeatable deployments. No test exams or marks were intentionally persisted during deployment.

## Flutter code

- `lib/features/exams/data/exam_repository.dart`: typed repository and authenticated Supabase RPC adapter.
- `lib/features/exams/presentation/exam_management_page.dart`: responsive school assessment page and interactive marks editor. No new top app bar on the Owner/Principal main shell. A detailed marks-editor route may have its own app bar.
- `lib/main.dart`: Owner navigation entry **Examinations**. Existing indices preserved; Examinations appended to avoid breaking existing wizard navigation.
- Principal main shell and staff workspace: expose Exams conditionally on permissions.
- `test/features/exams/exam_management_widget_test.dart`: view, create-form visibility, marks save and publication.
- `supabase/tests/DB20_EXAM_OWNER_ROLLBACK_INTEGRATION.sql`: zero-persistence, verified-owner transaction test.

## Usage

1. Sign in as Owner. Finish school setup with an active academic year and classes.
2. Open **Examinations** from sidebar (desktop) or More (Android).
3. Select a class, add a subject, then create a scheduled Exam, Test or Quiz. Select `All sections` or a specific class section.
4. Open the created item; enter marks or Absent for each enrolled student, then save.
5. Publish after all eligible students have marks/absences. Results become read-only.
6. To give a Principal exam access, Owner opens User Control Panel and grants `exams.read`, `exams.create`, `exams.update`. Teachers will require a future assigned-class-and-subject-scoped workflow; a broad permission toggle must not expose other classes.

## Important remaining work (not part of this delivered vertical slice)

- Multi-subject term/exam session aggregation, grade bands, rankings, cumulative report cards and official exam award lists.
- PDF date sheets, printable exam sheets, result cards, certificates and school-branded exports.
- Teacher-specific class/subject assignment checks and dedicated exam RPCs (teachers are intentionally denied broad access until implemented).
- Retake/rechecking, explicit re-open/versioned correction approvals and full history audit UI.
- Batch spreadsheet/CSV marks import and multi-student bulk-save optimization.
- End-to-end Android/Windows device validation and rollout performance with hundreds of students.

**Release gate:** Passing GitHub Flutter analysis/widget tests, an authorized Principal/Teacher trial, and the negative campus/role access test are still required before production readiness. Passing a manually simulated Owner transaction does not prove the installed client works.
