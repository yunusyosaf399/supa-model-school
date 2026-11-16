# Supa Model School — Login Background Assets

This directory is registered in `pubspec.yaml`. It must contain the
two user-supplied blank login backgrounds before testing final login visuals:

| Platform | Asset path | Image source | Crop |
|---|---|---|---|
| Windows desktop | `assets/login/signin_desktop.jpg` | User upload `1000311590.jpg` | Remove baked-in 43px Windows titlebar |
| Android portrait | `assets/login/signin_mobile.jpg` | User upload `1000311591.jpg` | Remove baked-in 49px status and 58px navigation bars |

The backgrounds are static artwork (logo / scene / window-style header and
footer included). They are behind **real** Flutter email, password,
campus-placeholder, sign-in, password reset, help, theme and demo controls.

**Asset transport:** The chat's uploaded image bytes cannot be written into
this repository through the current text-only GitHub file actions. They are
packaged separately in `SMS_Login_Backgrounds.zip` supplied in this chat.
Extract that archive **into the repository root**, keeping the
`assets/login/` directory intact. After extraction run:

```powershell
git status --short
flutter pub get
flutter analyze
flutter test
flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY
```

To commit the binaries to GitHub from your laptop after checking them:

```powershell
git add assets/login/signin_desktop.jpg assets/login/signin_mobile.jpg
git commit -m "assets: add approved login desktop and mobile backgrounds"
git push origin main
```

Asset checksums (SHA-256, cropped high-quality JPEG copies):

- `signin_desktop.jpg`: `64764e50bfbbe13c8aa0b39c48837e63ead2f04e5af5c734a8ca448565ffe8b3`
- `signin_mobile.jpg`: `ff0f2168b30d321059571d346f133d92f72d44c7b9e75baf7089bea426c5e3a2`

IMPORTANT: The supplied empty screenshots contain the baked-in text
**"Suffah Model School"** (not "Supa Model School"). The live form still
calls itself "Supa Model School". The screenshots are kept as submitted
except for crop; use replacement backgrounds if the artwork's displayed
school name needs correcting.

No change to live school records or authentication was made.
The School/Campus dropdown is intentionally placeholder-only before login:
this app verifies campus membership *after* Supabase authentication.
The Remember-me checkbox remains disabled until a secure encrypted
device-session store is implemented.
