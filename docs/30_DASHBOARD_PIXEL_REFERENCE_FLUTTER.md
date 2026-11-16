# Dashboard UI V2 — Flutter implementation of approved reference screens

**Date:** 2026-11-16
**Screens:** Windows desktop and Android dashboard
**Dependency:** existing Supabase Owner dashboard snapshot RPC and 2026-11-16 demo fixture.

## What changed
The previous dashboard was a simplified approximation. The dashboard has
now been rebuilt with Flutter widgets to closely reproduce the supplied
desktop and Android reference layouts, **without school or student images**.

### Desktop (large Windows window)
- Teal title bar, logo and sidebar menu, selected Dashboard gradient tile,
  photo-free subtle abstract curves, and a teal security/version footer.
- Toolbar: global search with Ctrl+K hint, authorized Owner campus,
  academic year, notification preview, and authenticated profile menu.
- Dashboard heading, four action buttons, four large stat cards with
  distinct icons, figures and sample-period delta badges.
- Two-panel central row: a structured four-row Recent Admissions table
  (student/class/date) and a real Flutter bar + trend-line fee chart,
  right-side summary, month labels and y-axis.
- Three-panel bottom row: green attendance donut and counts,
  yellow pending approval badges, and honest sync/backup status.

### Android
- School vector crest/name, authorized campus and notification/profile row.
- Soft blue-green, code-drawn wave greeting area (no photo).
- Tight 2x2 student/fee/outstanding/attendance metric tiles with badges.
- Four equal quick-action tiles.
- Compact recent admissions list with class pills.
- Three approval rows, sync status and a fixed teal-selected five-item
  bottom navigation bar.
- Lower-priority chart/attendance panels available by vertical scrolling.
- SafeArea navigation and breakpoints; desktop UI applies at available
  dashboard width >= 850 logical pixels.

### Data/permissions
- `DashboardSnapshot` is still populated only by the existing
  `SupabaseDashboardRepository` Owner/campus-scoped read-only RPC.
- The isolated seeded fixture still displays clear `TEST DATA`
  on both platforms, but a compact cream badge replaces the large yellow
  notice so the visual hierarchy matches the reference.
- Once Owner setup completes, the RPC switches to real DB02 school records.
  Fee, attendance, sync and backup modules still show
  `Not configured` if they are not implemented. No fabricated live values.
- No new Supabase migration, no real students, fees or documents written.
- Sign-in, Owner setup, admissions preview and password recovery untouched.
- No image assets were added. All gradients, footer effects, chart marks
  and circular indicators are drawn by Flutter.

## Source
- `lib/features/dashboard/presentation/dashboard_page.dart`
- `lib/features/dashboard/presentation/dashboard_visuals.dart`
- `lib/main.dart` (sidebar, desktop footer and mobile navigation)
- `test/features/dashboard/dashboard_reference_widget_test.dart`
- Existing login/Owner/widget smoke tests updated for the compact demo
  provenance disclosure.

## Design constraints
This is a fluid implementation, not an embedded screenshot. Exact pixel
dimensions will vary by Windows window scaling, Android density and
system font settings. At narrower widths, long currency values scale down
instead of overprinting and vertical sections scroll. Photos and the
reference screenshot's fictional profile headshots are deliberately
not inserted; a vector account avatar is used.

### Flutter verification
An experimental GitHub-hosted workflow was started but its job failed
**before any steps were executed**. It therefore did not run Flutter
analysis/tests and was removed from this feature branch. Do not represent
that job as a code-level test failure or success.

Run on the actual Windows laptop:

```powershell
git switch main
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

To inspect the reference layout without live credentials, use the existing
debug preview. This only uses marked sample data; it does not grant Owner
authorization. For real authenticated Owner data, sign in and open Dashboard.

If widgets overflow at a specific screen resolution or font scale, capture
the device width/height and the Flutter console output. Refine constraint
bounds rather than replacing widgets with background screenshots.
