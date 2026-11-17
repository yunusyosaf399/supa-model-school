# DB12 — Owner creates staff logins with initial passwords

**Updated:** 17 November 2026 — supersedes DB11's email invitation workflow.  
The Windows/Android app still uses the same **Owner Settings → Manage Users & Roles** screen; sidebar navigation is unchanged.

## Intended workflow
1. Owner enters **Name, Email, Initial Password, Confirm Password, Role and Campus**.
2. Only the verified Owner can call `owner-create-user` (Supabase Edge Function with JWT verification and backend Owner/campus preflight).
3. Edge Function uses its server-only Supabase Auth Admin client to call `auth.admin.createUser({email,password,email_confirm:true})`. No invitation or confirmation email is required.
4. A service_role-only RPC `public.server_register_created_user` rechecks Owner, school, exact newly created Auth identity/email, confirmed email, active campus and allowed nonprivileged role. It creates `user_profiles`, one campus `user_roles` assignment and an append-only `create` audit event.
5. The Owner gives the password privately to the staff member, who signs in immediately on Windows/Android using their school email/password.
6. **Principal** goes to the Principal Admissions workspace and can open **Change Password** from its app bar. Other supported staff roles reach a restricted **Account & Security** screen with self-service Change Password. The Owner already has a current-password-verified account change form.
7. Changing a password requires **current, new, and confirm** (12–128 characters with letters and numbers). Supabase Auth updates it and signs out the user. They sign back in with their new password.

No role other than Owner can create Auth credentials. Owner cannot create another Owner or Super Admin via the panel. Other staff roles have no access to Owner or Principal operations.

## Security and migration
- Auth passwords never go into public/student/school database columns, application logging, GitHub or generated documentation; Supabase Auth stores only its managed password hash.
- The Owner sees the initial password only while typing it; after successful creation the form clears both password fields. Share it via a private secure channel, not through a public chat, email thread or classroom notice.
- The Edge Function uses project secret/service-role credentials **only in the server runtime**. It runs identity validation and Owner preflight before creating a new Auth identity.
- New Auth accounts use `email_confirm:true` to support immediate login without an email invitation. This is a deliberate school-admin trust policy: the school Owner is responsible for checking the entered address.
- If database role assignment fails after Auth user creation, the Edge Function attempts to delete **only the just-created** Auth identity and reports the error without returning the password.
- Old `owner-invite-user` Edge endpoint is redeployed as a 410 Gone response. Legacy invitation registration RPCs are revoked. The previous DB11 invitation audit history remains intact.
- Staff password change uses `auth.updateUser` with current password and follows the existing Owner Auth change approach.
- Deactivating a staff role denies further role-authorized operations but does not automatically revoke all existing Supabase Auth sessions. Forced session invalidation is a separate administrative feature.
- The other staff role-specific operational dashboards are **not** implemented yet; their account and password management screen is available.

## Live manual acceptance
Run:
```powershell
git checkout main
git pull origin main
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Owner → Settings → Manage Users & Roles → Create User Login. Use a *new unused email* that you control, enter a secure initial password, choose **Principal** and **Main Campus**, then Create Account. Sign out. Sign in using the created email/password. Confirm the Principal approval list appears. Tap Change Password, enter current/new/confirm, and confirm sign-out; log in with the new password. Repeat with a Teacher account to test restricted Account & Security access.

**No real staff user has been created during CI/SQL tests.** The DB12 rollback test proves authorization, role/audit creation, and staff-role isolation with a temporary artificial Auth row; it does not test actual HTTP Admin `createUser` on a live mailbox. Full Windows/Android live credential acceptance still needs a real user-created test account.

## Source
- `supabase/functions/owner-create-user/index.ts`
- `supabase/functions/owner-invite-user/index.ts` (disabled, HTTP 410)
- `supabase/migrations/20261117165236_db12_owner_direct_user_create_20261117.sql`
- `supabase/migrations/20261117165454_db12_staff_session_context_20261117.sql`
- `supabase/tests/DB12_OWNER_DIRECT_STAFF_CREATE_INTEGRATION.sql`
- `lib/features/owner/presentation/owner_user_control_panel_page.dart`
- `lib/features/auth/presentation/account_password_page.dart`
