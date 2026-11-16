# Supa Model School — Login Background Assets

Both user-supplied blank background images are **committed in GitHub**
on this branch and declared in `pubspec.yaml`:

| Platform | GitHub asset | Original upload | Transform |
|---|---|---|---|
| Windows | `assets/login/signin_desktop.jpg` | `1000311590.jpg` | Removed top 43px baked-in window caption |
| Android | `assets/login/signin_mobile.jpg` | `1000311591.jpg` | Removed 49px baked-in status bar and 58px bottom navigation bar |

The photographs, foliage, logo, text and teal framing remain unchanged.
Flutter displays the interactive login form on top of the fixed background.

### Verified GitHub blob hashes

- Desktop: `6b17351b1bdcb44dd5993d05037317af477927e0`
- Android: `456c59b9b0811c7d4f8967a964290681420b34b2`

These hashes were checked against the uploaded local JPEG bytes after
cropping. **No extra asset extraction is necessary:** `git pull` is enough.

### Laptop commands

```powershell
git pull --ff-only origin main
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

The user's empty images contain baked-in branding **"Suffah Model School"**
while the application and form still use **"Supa Model School"**. The asset
content was not retouched; use a revised approved background if this spelling
must match.

The School / Campus pre-auth selector is intentionally disabled until
authenticated campus lookup is available. Remember me stays disabled until
secure encrypted session persistence is implemented.

The downloadable chat ZIP is an optional backup, not required for use.
