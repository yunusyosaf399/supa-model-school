# Owner Academic Structure: Classes & Sections

**Created:** 2026-11-16
**Branch:** `feature/owner-academic-structure-20261116` (stacks on PR #15 and PR #14).

## Purpose
Allow the authenticated School Owner to create **actual class/section masters** in
the selected campus and active academic year, ready for future student admissions,
class allocation and subject/teacher mapping.

Do not create demo school data or silently choose the school's academic year.

## Implemented in live Supabase
Migration version **20261116081604**, name
`db01_owner_academic_structure_20261116`, deployed to project
`uebzvfzpbqqttbqyxxos`.
Tracked repository migration:
`supabase/migrations/20261116081604_db01_owner_academic_structure_20261116.sql`.

Additive changes:
- Case-insensitive uniqueness on `classes(campus_id,academic_year_id,name)`.
- Case-insensitive uniqueness on `sections(class_id,name)`.
- New RLS-enabled, Owner-read-only `academic_structure_audit_events`.
- Atomic `owner_create_class_with_sections` RPC (public SECURITY INVOKER
  wrapper and unexposed `app_private` SECURITY DEFINER implementation).
- No authenticated direct SQL INSERT/UPDATE on `classes`, `sections`,
  or academic audit records, no anonymous RPC execution.

### Authorization
The database verifies Supabase Auth identity (confirmed, nonanonymous,
not deleted), active user profile, active school-wide Owner role and matching
school/campus/active academic year. It additionally verifies
`school_settings.initial_setup.status = complete`.

The Owner may create a class with 1–12 section names, each 1–50 characters.
Class names must be 1–100 characters; sort order 0–1000. Whitespace and
case variants of an existing class/section cannot create duplicates.
A lock on the active year serializes concurrent class creation. Every
successful creation writes an audit event in the same transaction.

## Flutter implementation
- `lib/features/academics/data/academic_structure_repository.dart`: real
  scoped reads from `classes` and `sections` via RLS, authorized RPC writes.
- `lib/features/academics/presentation/academic_structure_page.dart`:
  light/dark responsive Owner management page with campus dropdown, active
  year context, class/section creation, list, refresh, loading and error states.
- `lib/features/auth/data/owner_auth_gateway.dart`: returns verified
  `activeYearId` for scoped queries.
- `lib/main.dart`: new `Academic Setup` navigation entry; only authorized
  Owner uses real page. Preview mode cannot create live records.
- `lib/features/owner/presentation/owner_control_panel_page.dart`:
  shortcut to `Manage Classes & Sections` after initial school setup.

### Workflow
1. Sign in with the existing Owner credentials.
2. Complete real Owner school setup (school name, campus, currency,
   timezone, active year) in Settings, if still pending.
3. Choose **Settings → Manage Classes & Sections** or **Academic Setup**.
4. Choose authorized campus, enter a class name such as `Grade 1`,
   section names such as `A, B`, optional sort order, then Create Class.
5. The backend authorizes, creates and audits one transaction. The UI reloads
   the real records for the selected campus and academic year.

The dropdown uses actual authenticated school/campus/academic-year IDs, not
preview UUIDs.

## Testing
- The hosted migration applied successfully and exists in migration history.
- Rollback-only SQL fixture `supabase/tests/DB01_ACADEMIC_STRUCTURE_RLS_INTEGRATION.sql`
  **passed**, including denial while initial school setup is pending,
  unknown actor denial, duplicate casefold sections rejection, successful
  authenticated Owner class/sections/audit creation, and duplicate class
  rejection. All test writes rolled back.
- Live checks after migration: no classes, no sections, no academic years,
  no academic audit events. Initial school setup remains pending.
- Supabase Security Advisor: leaked-password protection disabled warning;
  no new missing-RLS or public-RPC-execute warnings.
- Flutter widget tests authored at
  `test/features/academics/academic_structure_widget_test.dart`.
  No Flutter SDK is available in this tool environment, so analyzer,
  widget tests and Windows/Android runtime **not executed here**.
- PR is draft; merge only after the user's local validation and the dependent
  PRs merge in order.

## Next boundaries
This task does **not** write student records, admissions, fees or attendance.
Next connect DB02 admissions to authorized campuses/academic-years/classes/
sections, subject to DB02 storage policies and principal approval testing.
Parent/teacher scoped permissions and academic-year rollover remain separate.
