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

**GitHub binary assets are committed and verified.** Both uploaded JPEG
backgrounds were transferred into GitHub Git blobs and attached to this UI
branch, then checked against the exact local image content. The Flutter
`pubspec.yaml` asset registration and both files are version-controlled.
No manual ZIP extraction, copy or asset push is required. The chat ZIP
is an optional backup only.

On Windows, open PowerShell in the repository root:

```powershell
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
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

## Desktop compact-card correction — 2026-11-16

After reviewing the user's first Windows screenshot, the desktop login form
was made **narrower and shorter** and shifted downward to keep the top-right
appearance and debug-preview icons completely unobstructed.

- Desktop card width: `min(470, windowWidth × 0.335)` logical pixels.
- Desktop card top: `max(76, windowHeight × 0.108)` logical pixels.
- Reduced desktop internal padding and vertical spacing (mobile values
  unchanged), while keeping all existing accessible login controls.
- New widget regression assertions cover the card width and top offset.

This is a layout-only correction: no change to Auth callbacks, Supabase
settings, image assets, or database schema. Flutter runtime rendering must
still be verified on Windows.
