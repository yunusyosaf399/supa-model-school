# D03-T05 — Student directory and search UI

**Status:** Flutter source authored on draft [UI PR #7](https://github.com/yunusyosaf399/supa-model-school/pull/7). Static source review only. Flutter analysis, build, widget tests and authenticated database integration have NOT been executed.

## UX / screen inventory
- Students navigation opens `StudentDirectoryPage` on both Windows desktop and Android.
- Windows desktop (width >=850): searchable table columns Student, Registration, Campus, Class/Section, Academic Year, Status and View.
- Android/smaller screens: touch-friendly stacked cards.
- Search is case-insensitive for the *name and registration number only* (no sensitive guardian fields).
- Filter selectors: authorized campuses, permitted classes and student status. Class filter resets whenever campus changes.
- Status labels: Active, Inactive, Withdrawn, Graduated.
- Clear filters restores the scoped record collection; empty results show an explicit message.
- Tapping View opens a read-only Student Profile (preview) with basic class and enrollment fields, and no fee/guardian/document data.
- "New admission (preview)" still opens the six-stage D03-T04 wizard.

## Privacy and authorization boundaries
**Important:** The `StudentDirectoryProjection` is an in-memory demonstration of presentation filtering. It is NOT a security barrier.

- All bundled student examples are imaginary, labeled DEMO and belong to *Sample Campus A*.
- No real student, government ID, guardian phone, health details, receipt, or document URL is included.
- `authorizedCampusIds` filters UI results and available campus options, but the backend MUST apply the actual user-role/campus permissions **before** returning data.
- The designated offline Windows desktop stores ONLY records from its assigned authorized campus in encrypted/protected SQLite. It must never prefetch foreign campuses merely because the Owner might sometimes browse them online.
- Online owner/principal multi-campus access must be separately authorized and should not be cached in the campus offline store.
- Data API query, RLS and Storage policies must enforce all restrictions; filtering a broad query in Dart cannot protect data.
- Profiles must be fetched from a separately authorized endpoint; opening a URL by guessed student UUID must not leak records.
- Search results, result counts, reports and CSV exports must use the same campus-scoped permission boundary.

## Existing data source
`StudentDirectoryDemo.projection` provides four obviously fictional students and one sample campus. It is not a Supabase query, an authenticated repository, or a database cache. Record identifiers begin `demo-` or `DEMO-` and are NOT valid UUIDs.

## Future backend contract (not implemented)
1. Authenticate the session and determine active school/campus/role permissions.
2. Online clients query a narrowly scoped authorized student search endpoint, with server-side pagination, validated campus/year/class/status filters and search.
3. Return a **minimal projection**: student UUID, registration number, display name, campus ID/name, current enrollment class/section, academic year and status.
4. Do not join guardians, documents, fees or medical details into broad directory queries. Fetch authorized detail separately.
5. On offline main desktop, the local repository returns only the assigned-campus student projection and syncs only allowed changes.
6. Record counts and campus choices must be computed using authorized data, not globally cached results.
7. Handle expired authorization, school/campus transfer, profile revocation, sync gaps and pagination securely.
8. The existing demo should be removed when real Supabase Auth/RLS and Drift repository are tested.

## Automated test source
- `test/features/students/student_directory_model_test.dart`: permitted-campus records, unauthorized-campus exclusion, name/registration search, class/status combinations, fictional-only sample data.
- `test/features/students/student_directory_widget_test.dart`: mobile header, search and empty state, reset, read-only profile route, desktop table, unauthorized data filtering in demo preview.
- `scripts/check_student_directory_ui.py`: lightweight static code sanity checks, not Flutter compilation.

## Laptop acceptance checklist
- [ ] `flutter doctor -v` passes on developer's Windows environment.
- [ ] `flutter pub get`, `flutter analyze`, `flutter test` pass.
- [ ] Windows table and filter layout tested at multiple widths.
- [ ] Android portrait list, scrolling and touch targets tested.
- [ ] Search finds fictional name and registration numbers and clears correctly.
- [ ] Status/class filters and empty state behave correctly.
- [ ] Student profile opens from table and card without exposing private fields.
- [ ] Admission button still opens wizard from Students.
- [ ] Role/campus isolation is proved on server before real data is enabled.
- [ ] No student data or app secrets are committed; no real user data fetched.
- [ ] All relevant RLS and offline cache isolation tests pass before launch.

**Do not mark live student search, RLS or sync integration complete based on this UI PR.**
