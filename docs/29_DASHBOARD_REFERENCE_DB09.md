# Supa Model School — Dashboard UI and DB09 Read-Only Snapshot

**Date:** 2026-11-16  
**Repository:** `yunusyosaf399/supa-model-school`  
**Supabase:** `uebzvfzpbqqttbqyxxos`  
**Scope:** Windows / Android dashboard only; no admissions or finance write UI.

## Design implementation

The desktop dashboard follows the supplied desktop reference:

- Slim teal application title bar, school logo, left white sidebar and user
  supplied building image in the bottom of the sidebar.
- Global search entry, verified Owner campus selector, active/demo year,
  notification preview and authenticated account menu.
- Dashboard header with four quick actions: New Admission, Collect Fee,
  Take Attendance and Record Expense.
- Four responsive metric cards: Active Students, Fee Collected,
  Outstanding Fees, and Today's Attendance.
- Recent Admissions and six-month Fee Collection Trend in middle row.
- Attendance Summary, Pending Approvals and Sync/Backup Status in bottom row.

The mobile dashboard follows the supplied portrait reference:

- School logo, school name, Owner campus and account actions.
- Good morning banner with the school's photo extracted from the user's
  reference image.
- Two-column metric cards, a four-tile quick action strip.
- Recent Admissions, Pending Approvals and Sync Status panels above existing
  bottom navigation.
- Responsive scrolling for narrow Android devices and Windows small windows.

Source files:
- `lib/features/dashboard/presentation/dashboard_page.dart`
- `lib/features/dashboard/data/dashboard_repository.dart`
- `lib/main.dart`
- `assets/dashboard/school_hero.jpg`
- `assets/dashboard/school_sidebar.jpg`
- `pubspec.yaml`
- `test/features/dashboard/dashboard_reference_widget_test.dart`

### Authorization and live data source

The Supabase migration
`20261116150449_dashboard_owner_demo_readonly_projection_20261116.sql`
creates:

1. `app_private.dashboard_demo_snapshots`, a **private RLS-protected**
   fixture table with no direct client grants.
2. `app_private.owner_dashboard_snapshot(uuid,uuid)`, a SECURITY DEFINER
   function checking the verified Auth user, active Owner membership,
   active profile, active school and selected active campus.
3. `public.owner_dashboard_snapshot(uuid,uuid)`, an explicitly granted,
   read-only SECURITY INVOKER RPC to be called with the publishable client
   key and authenticated session. Anonymous callers have no EXECUTE grant.

`SupabaseDashboardRepository` only calls this authorized RPC. It never
directly queries protected student, guardian, admission or document tables.

### The test dataset — IMPORTANT

Because the existing Owner school has **not completed initial setup**
(0 academic years, 0 classes, 0 students), a database fixture has been
inserted into `app_private.dashboard_demo_snapshots` for its single campus.

The seed `supabase/seed/20261116_dashboard_demo_only.sql` contains
explicitly labeled **fictional** figures:

- 1,248 sample active students
- PKR 4,860,750 sample collected fees and PKR 742,500 sample outstanding
- 1,215 / 1,248 sample attendance
- Six sample fee trend months
- Four `Demo Student ...` recent-admission entries
- 7/4/3 example admission/expense/leave approval counts

These are **not rows in operational students/admission/payment tables**.
No fictional Auth users were created. No school name, pending setup
settings, first Owner record, academic year, classes or real student
identity were changed to insert demo data.

Every dashboard fixture response has:
`is_demo=true`, `source=database_test_fixture`, and a prominent
**TEST DATA** notice in Flutter.

**Automatic transition to real data:** once the Owner completes real
school setup and an active academic year exists, the same RPC returns
real campus/year student counts and approved/pending admission data. It
stops returning the demo fixture automatically.

Since finance, attendance, payroll, approvals beyond admissions, offline
device sync and backup are not operational in this version, the real
dashboard returns NULL/unavailable for their metrics. The UI shows
`Not configured` instead of inventing financial or sync records.

### Test evidence

Executed rollback-only SQL integration test:
`supabase/tests/DB09_DASHBOARD_RLS_INTEGRATION.sql`.

Tests passed:
- No anonymous RPC permission; no direct authenticated fixture table read.
- Authorized verified Owner can see the same-campus demo fixture.
- Unknown user is denied with insufficient_privilege.
- Temporary school setup/year/student enrollment inside ROLLBACK switches
  to live mode with 1 active student, and financial/attendance NULL.
- All temporary live student/year setup edits were rolled back.

Verified after seeding: exactly 1 demo snapshot; zero operational students,
applications and academic years; Owner setup still `pending`.
Supabase migration history lists version `20261116150449`.

The Flutter UI source includes reference-layout tests and preserves
existing sign-in, navigation and Owner setup behavior. **Flutter analyzer,
widget runtime, Windows and Android screen rendering were not executed**
in the assistant runtime (no Flutter SDK). Run them on the user laptop.

### Test on Windows

```powershell
git switch main
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

Login with the existing Owner credentials, then open **Dashboard** from
the sidebar (Owner setup is still pending, so first sign-in starts at
Owner Control Panel). The **TEST DATA** banner and reference cards should
be visible. No real admission submission/fee collection is enabled.

### Cleanup

The fixture is isolated and automatically hidden once setup completes.
If it should be deleted explicitly, a database administrator can execute:

```sql
delete from app_private.dashboard_demo_snapshots
where snapshot->>'is_demo'='true';
```

Do not delete operational student or enrollment records as part of
dashboard demo cleanup.
