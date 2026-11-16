# First School Owner — Secure Auth Bootstrap and Flutter Wiring

**Status (2026-11-16): Source committed; LIVE account NOT provisioned.**
**Project:** Supa Model School, Supabase ref `uebzvfzpbqqttbqyxxos`.

## Live readiness review
- At inspection: zero `auth.users`, zero DB01 foundation tables, zero applied migrations.
- The connected Supabase management plugin does not expose the Auth Admin `inviteUserByEmail` action.
- No confirmed Owner email, first-campus name, school currency, or timezone was explicitly assigned by the school owner.
- Do **not** make up an email/password, manually edit `auth.users`, or put a service-role/secret key into Flutter.

## What has been implemented in source
- `lib/features/auth/data/owner_auth_gateway.dart`: production Supabase email/password authentication through `signInWithPassword`; `getUser()` verified identity; active `user_profiles`; unique active school-wide `owner` membership in `user_roles`; active `schools`; authorized active `campuses`; denial signs out the Auth session.
- `lib/main.dart`: initialize with `SUPABASE_URL` and the **publishable** key supplied through Dart defines; restore an existing session only after revalidating Owner role. Distinct debug design preview mode. In-memory-only Auth storage with `EmptyLocalStorage`: sessions are intentionally not persisted across app restarts until encrypted platform-specific storage is tested. Owner's campus list only appears after authorization. Sign out removes authentication.
- `lib/features/auth/presentation/login_page.dart`: real email/password sign-in callback, disabled sample campus selection for configured auth, errors that do not enumerate users, no fake sign-in.
- `pubspec.yaml`: pinned stable `supabase_flutter 2.18.3` for Dart 3.9.
- `supabase/drafts/DB01_FIRST_OWNER_ACTIVATION_TEMPLATE.sql`: privileged, one-use **data bootstrap template**, explicitly NOT a migration or an Auth user creation script. Fails closed for missing verified email, missing config, or pre-existing school/Owner.

## Required action to activate one real Owner (not yet performed)
1. Review and execute DB01 foundation as a versioned migration in an isolated local Supabase stack. Run the existing `supabase/tests/DB01_RLS_INTEGRATION.sql` with its seven local fictional Auth accounts, and confirm campus/cross-school denials, settings privacy, and client write denial.
2. Once tests pass, deploy DB01 foundation migration to the correct Supabase project; verify 12 RLS-enabled tables and security advisors. DB01 must be deployed before step 4.
3. In [Supabase Authentication → Users](https://supabase.com/dashboard/project/uebzvfzpbqqttbqyxxos/auth/users), choose **Add user → Send invitation** for the intended Owner's specified email. The invite recipient must accept, verify their email, and choose a strong password. Do not share the password in chat.
4. In the trusted **SQL editor** only, open `DB01_FIRST_OWNER_ACTIVATION_TEMPLATE.sql`. Replace the explicit Owner email, display name, school ISO currency code, IANA timezone, and first campus name. Run exactly once after verifying these inputs. The template creates the school, first campus, active profile, and exactly one school-wide `owner` role in an atomic transaction. The role must have `campus_id = NULL`.
5. Verify the owner role row exists; test legitimate Owner campus access and negative account/campus access with real auth sessions. Confirm no anonymous client writes or self-grant route. Do not use live student records yet.
6. Only then run the Flutter client with the project URL + publishable key provided by the project dashboard. Sign in using the Owner's chosen password.

### Local Flutter commands
```powershell
git fetch origin
git switch auth/first-owner-bootstrap-20261116
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test

flutter run -d windows --dart-define=SUPABASE_URL=https://uebzvfzpbqqttbqyxxos.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Use only the **public/publishable** key (or legacy anon key where necessary); never the service-role or `sb_secret_` key. Create local, uncommitted run settings for the public values as needed.

### Password changes
The actual password is managed by Supabase Auth, **not** `user_profiles`, `user_roles`, or a custom school password column. The intended future path is **Settings → Account & Security → Change Password** using Supabase `updateUser()` for an authenticated Owner with an appropriate reauthentication policy. Until a tested recovery redirect route exists, the UI does **not** falsely claim password reset is enabled; the school administrator can use the Supabase Auth admin interface to send an invitation/recovery process. Secure email recovery and deep-link routes are still pending.

## Security and release gates
- Do not deploy untested DB01 SQL to live or merge this PR into production without RLS evidence and a real invited account.
- The debug `Preview Dashboard` route is not a substitute for a verified Owner session and remains removed from release builds.
- Dashboard counts and other feature modules are still synthetic previews, even for an authenticated Owner.
- School-owned settings and user role grants are Owner-only by intended policy but editing them is not implemented.
- Real RLS and API grants, transaction integrity, audit, revocation, email verification, MFA and secure session storage require integration tests.
- The exact email identity and campus/school configuration remain inputs, not guessed values.
