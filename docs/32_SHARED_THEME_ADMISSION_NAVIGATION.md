# Shared Theme and Navigation — Dashboard ↔ Admissions

**November 16, 2026 — Flutter-only correction**

## Problem reproduced from user screenshots

- Dashboard remained dark, while opening **New Admission** suddenly showed a
  light screen. The wizard was wrapped in `Theme(...copyWith(colorScheme:
  ColorScheme.fromSeed(...), scaffoldBackgroundColor: light...))`, which
  explicitly forced light surfaces.
- Dashboard and Admissions each declared independent toolbar styles; the
  global-search control had a different silhouette, size and spacing.
- Admissions used a separate route with an inert, decorative sidebar, inert
  toolbar search and notifications; links to other modules could not navigate.
- App appearance was visible in the normal top AppBar instead of Settings.

## Implemented

1. **Single theme source:** the app's existing `MaterialApp.themeMode` stays
   authoritative. No admissions color scheme or light background override.
   Admission inputs, cards, sidebar, modal text and borders now use adaptive
   dark/light colors. Switching appearance in Settings updates dashboard,
   Admissions and the remaining implemented feature modules.
2. **Settings only (authenticated shell):** AppBar theme chooser removed;
   appearance selector is displayed in the Settings screen. The existing
   pre-login screen is unchanged to avoid redesigning a previously approved
   flow. The theme change applies across navigation and is held in app state;
   persistence across application restarts is not implemented here.
3. **Consistent toolbar:** Admissions search uses the dashboard's 46px-high
   outlined, 11px-radius search styling, magnifier, placeholder and Ctrl+K
   hint. Campus/year controls are 43px high, with a real verified campus
   selector (when multiple authorized campuses exist). Account includes
   Settings and a leave action. Notification button shows an honest
   not-configured message.
4. **Real navigation:** Admissions desktop sidebar now has tappable
   Dashboard, Students, Fees, Attendance, Employees, Payroll, Expenses,
   Reports, Sync Center, Settings and Academic Setup items. Changing modules
   prompts for confirmation before discarding the in-memory admission draft.
   After confirmation the route closes and the parent `_SchoolShell`
   changes its selected module, retaining auth and theme state.
5. **Academic scope:** The verified campus selection is passed into the
   wizard on opening, classes are loaded for that campus when academic setup
   is ready, and campus changes notify the parent shell. No synthetic
   campus/class identifiers.
6. **No changes** to dashboard cards/chart design, login backgrounds, fee
   posting, actual admission submission or database schema.

## Verification
- Source-level consistency checks for edited files, callbacks, adaptive
  theme and navigation wiring.
- Widget-test source added to cover dark-mode inheritance, search callback
  and discard-confirmation navigation.
- **Flutter SDK unavailable here:** Flutter analyzer, Windows/Android
  builds and widget-test execution are not verified until run locally.

```powershell
git switch main
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

**Manual test:** Settings → Appearance → Dark; Dashboard → New Admission.
The admission surface and text should be dark. Test the search field,
Admissions sidebar → Dashboard, confirm discard, and Settings → Light →
New Admission. Navigation should preserve the selected theme.
