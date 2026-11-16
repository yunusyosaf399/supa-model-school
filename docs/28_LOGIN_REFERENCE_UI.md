# Login UI — Supplied Windows / Android Reference Layout

**2026-11-16 | Scope: Login screen only**

The first login screen is now implemented in
`lib/features/auth/presentation/login_page.dart`, using the user's two
empty reference images as **background artwork** with an actual responsive
Flutter `Form` overlaid above the picture.

## Intended visual match

- **Windows ≥900 logical px and landscape:** background image fills the
  window content; the white rounded card overlays the right edge, with a
  slight right margin, anchored beneath the native Windows window caption.
  Artwork already contains the school/trees/students/footer; these are NOT
  duplicated in Flutter.
- **Android / narrow windows:** portrait background fills the screen;
  responsive card occupies the central gap beneath the baked-in logo and
  above the school students scene. The form can scroll when the keyboard
  opens and the background remains stationary.
- **Labels and controls:** School / Campus placeholder, Email or Username,
  password with visibility toggle, Remember me, Forgot Password, teal Sign
  In button, English first note and Contact administrator help link.
- The theme chooser and debug-only preview remain reachable at the top-right
  of the screen. The real Supabase Owner sign-in and password reset callbacks
  are unchanged.

## Asset paths (required for the intended appearance)

`pubspec.yaml` registers `assets/login/`:

- `assets/login/signin_desktop.jpg`
- `assets/login/signin_mobile.jpg`

**Critical transfer note:** the GitHub repository update mechanism in this
session accepts UTF-8 text only. It cannot ingest the attached JPEG bytes
directly, so the exact uploaded user-image assets are delivered as
`SMS_Login_Backgrounds.zip` in the same ChatGPT response. The GitHub PR
contains the UI source, `pubspec.yaml`, tests and this documentation, but
**does not contain the two actual JPEG files** until the user extracts them
on their laptop and pushes them once. A neutral gradient fallback prevents
missing assets from crashing the login screen.

On Windows, open PowerShell in the repository root and extract the
downloaded ZIP (adjust path if Downloads is different):

```powershell
git pull --ff-only origin main
Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\SMS_Login_Backgrounds.zip" -DestinationPath . -Force
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

**When satisfied with screenshots, publish backgrounds:**

```powershell
git add assets/login/signin_desktop.jpg assets/login/signin_mobile.jpg
git commit -m "assets: approved Windows and Android login backgrounds"
git push origin main
```

### Artwork processing
The supplied empty images were **not synthesized**. The two uploaded JPEGs
were cropped only to remove fake OS chrome embedded in screenshot image:
desktop: remove top 43 pixels (Windows title bar); mobile: remove top 49
pixels (status bar) and bottom 58 pixels (Android navigation bar). Both
remain high-quality JPEG at their respective native widths.

The images themselves say **"Suffah Model School"**, exactly as uploaded,
while the Flutter form currently says "Supa Model School" (current app
brand). For consistent branding, replace the supplied artwork with an
approved image containing the desired school name; do not assert the
background text was automatically edited.

### Security behavior
- School/campus cannot be selected before authentication because the
  deployed Auth gateway validates and retrieves verified campus memberships
  only after Supabase sign-in. The visual field is a placeholder and
  disabled (no fictional school IDs).
- Remember me remains disabled until encrypted local session persistence
  and revocation are implemented.
- Password visibility works; password is not saved by this screen.
- Password reset uses the existing callback with registered email.
- Debug preview does not grant authenticated rights.
- This task does not touch any database migration, school records, admissions
  approvals or other screens.

### Verification
Source-level checks can verify the two asset references, responsive
breakpoint, form keys, and preserved callbacks. Real Flutter analyzer, widget
tests, and Windows/Android screenshots must be run on the user's machine;
the current tool environment has no Flutter/Dart SDK. New test source:
`test/features/auth/login_reference_layout_widget_test.dart`.
