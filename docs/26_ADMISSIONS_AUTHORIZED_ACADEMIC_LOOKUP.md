# Admission Wizard — Authorized Academic Lookup (DB01 → DB02 UI bridge)

**Date:** 2026-11-16  
**Branch:** `feature/admissions-live-academic-lookup-20261116`  
**Dependency:** Academic Setup PR #16, which depends on Owner/Auth PR #15 and Login/Theme PR #14.

## Result

The admission wizard's **Academic** step now uses the authenticated Owner's verified
school context and live, RLS-filtered DB01 class/section records. All fictional
campus, academic-year, class and section choices have been removed.

- **Campus:** comes from the `OwnerAccess.campuses` list, populated by the
  verified Auth + `campuses` RLS read. Never use unauthenticated global lookup.
- **Academic year:** `OwnerAccess.activeYearId` and `activeYearLabel`, read
  from the server-side active school year only. Previous academic years remain
  accessible elsewhere in the product, but are *not* selectable for a new
  admission in this initial UI.
- **Class:** live `classes` rows using `campus_id` plus
  `academic_year_id` query constraints.
- **Section:** live `sections` rows, filtered using the selected class's
  authorized IDs. The section selection remains optional at this UI phase;
  any later admission finalizer must enforce its class allocation policy.

Choosing a different campus invalidates the old pending lookup and clears
previous class/section selections; selecting another class clears the section.
A failed lookup is shown with a retry action, and blocks progression to
documents. An empty campus/year reports that Owner must add classes in
`Academic Setup` rather than offering fictitious choices.

## Security and data provenance
The wizard receives `OwnerAccess` only after Auth/role/school/campus checks.
It calls the existing `AcademicStructureRepository.listClasses()` read-only
method, protected by DB01 RLS. The app never uses a service-role key.

**Crucially, the admission wizard is still a preview.** It holds student
name/DOB, guardians, academic IDs, document deadline, and fee intentions only
in Flutter memory. It does not write to `students`,
`admission_applications`, `student_documents`, Storage, offline outbox,
payment ledger, or send approval notifications. The final Submit button
remains disabled. The DB02 admissions schema is a review draft and has not
been applied to Supabase.

Without an authenticated Owner context or if setup is incomplete, the
Academic step displays **no sample choices** and explains the prerequisite.
The user cannot proceed using placeholder UUIDs.

Real academic IDs must be **revalidated by the future trusted DB02 admission
operation**. Frontend filtering alone is not an authorization mechanism, and
data can change between selection and submission.

## Source files
- `lib/features/admissions/presentation/admission_wizard_page.dart`
- `lib/features/admissions/models/admission_draft.dart`
- `lib/main.dart` (passes only verified Owner and authorized academic repo)
- `test/features/admissions/admission_academic_lookup_widget_test.dart`
- `supabase/tests/DB01_ADMISSION_ACADEMIC_LOOKUP_RLS.sql`

## Database verification (2026-11-16)

Executed `DB01_ADMISSION_ACADEMIC_LOOKUP_RLS.sql` against the connected
hosted Supabase project in a single transaction with a final ROLLBACK.

- In-school Owner could read the test year, campus, class and section.
- A different school's test records remained invisible.
- A claimed but unknown user ID could read none.
- Anonymous table SELECT and direct class INSERT grants were absent.
- No academic-year, class or section test rows persisted.

**No new schema migration was necessary for this task.** Existing DB01 RLS
`school_read`, `campus_read`, `year_read`, `class_read`, and `section_read`
policies protect the lookup. No DB02 schema or Storage changes were applied.

## Pending laptop testing

On the dependent branch chain, run:

```powershell
git fetch origin
git switch feature/admissions-live-academic-lookup-20261116
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

To test with real rows, complete Owner school setup and create classes/sections
through the deployed RPC first. Then sign in with the existing Owner account,
open New Admission, navigate to Academic, and test campus/class/section
selection, reset behavior and the disabled submission state.

No Flutter/Dart SDK is present in the assistant environment, so UI compilation,
widget test execution, real Owner-password login, and Windows/Android runtime
verification are **not claimed** as passed.

## Next work

DB02 admissions deployment requires its own reviewed migrations, audit/RLS
tests, private document-storage policies, intake draft operations, principal
approval/finalization transaction, guardian/student identity rules, and
conditional-document deadline validation. Only after those checks should the
Submit button be enabled.
