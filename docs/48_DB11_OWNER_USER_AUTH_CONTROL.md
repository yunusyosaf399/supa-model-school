**Superseded by DB12 (17 November 2026).** The email invitation flow described below is disabled. The Owner now sets an initial password directly; see [DB12 Owner Direct Credentials](49_DB12_OWNER_DIRECT_CREDENTIALS.md).

# DB11 — Owner User Control Panel (Supabase Auth)

The live school Owner can now manage school users from **Owner Settings → Manage Users & Roles** without changing the left navigation. Invitations are **email-based**: the Owner never sees or sets staff passwords.

## Flow
1. Owner enters full name, email, an allowed staff role and an active campus.
2. Flutter calls `owner-invite-user` Edge Function with the signed-in Owner's JWT; public client key only.
3. The Edge Function validates Auth JWT using `auth.getUser`, then calls authenticated `owner_user_invite_preflight`. Invalid Owner, campus or role is denied *before* invitation.
4. Server-only `auth.admin.inviteUserByEmail` sends an invitation. `SUPABASE_SERVICE_ROLE_KEY` is read inside the Edge Function runtime only, **never in Flutter or GitHub**.
5. A `service_role`-only public invoker bridge calls the private registration transaction. It rechecks confirmed active Owner, the exact invited Auth email, newly created/unconfirmed invitation identity, active campus, and allowlisted role before inserting `user_profiles` and `user_roles` with an audit event.
6. Invitation recipient completes email/password setup. After confirmed sign-in, the school Principal is routed to the existing **Principal Admissions** workspace.
7. Owner can list school-scoped users, search name/email/campus/role and deactivate/reactivate **staff role assignments**. Owner and Super Admin role edits are prohibited. No student or historical audit data is deleted.

**Allowed invitations:** Principal, Vice Principal, Administrator, Accountant, HR, Teacher, Coordinator, Librarian, Transport Manager, Driver, Nurse, Store Keeper, Security Guard, Parent/Guardian and Attendance Staff. The Owner cannot invite another Owner or Super Admin using this panel.

## First real test
Run updated Windows debug app and sign in as the current school Owner. Navigate to Settings → Manage Users & Roles, invite a **new, unused email address** as Principal for Main Campus. Open the invitation email, set the password, sign out of Owner, sign in as Principal and confirm **Principal • Admission Approvals** loads, then switch back to Owner and test Deactivate/Reactivate. Test with fictional staff data and a mailbox you control.

**Auth email prerequisite:** In Supabase Dashboard → Authentication → URL Configuration, configure the Site URL to a real supported sign-in/password setup page, not the default localhost test URL. Configure and test email delivery in Supabase Auth; free-tier mail limits/provider restrictions may prevent external email delivery. A Windows native deep-link password-setup route is not implemented yet, so invitation acceptance may require a web-based Auth setup URL. A valid email invitation is not proof that a staff member can complete onboarding until this is tested.

## Security / limitations
- RLS on private audit table; role creation and staff status changes happen through independently authorizing SQL functions.
- An already assigned Auth identity cannot be silently invited again or transferred to a different school.
- Do **not** store or embed service-role/secret keys in Flutter, GitHub Actions, build scripts or source code.
- Turning off a role takes effect at the next authorized server call, but it does not revoke an existing Auth session. Disabling a staff member in Auth entirely or revoking all of their active sessions requires a separate server-side admin action.
- Staff role assignment is one campus/one role per invite in this version. Assigning multiple campuses/roles and transferring an existing Auth account requires a separate auditable workflow.
- Principal backend is end-to-end role-tested in rollback transactions, but inviting an actual live email and completing password setup is a pending device/email acceptance test.
- New users other than Principal can sign in with Auth, but their role-specific dashboards are not built; the app currently routes non-Owner/non-Principal sign-ins back to the login gate.

## SQL and code
- `supabase/migrations/20261117162705_db11_owner_user_management_20261117.sql`
- `supabase/migrations/20261117162855_db11_user_invite_service_bridge_20261117.sql`
- `supabase/migrations/20261117163312_db11_recent_invite_role_assignment_hardening_20261117.sql`
- `supabase/functions/owner-invite-user/index.ts`
- `supabase/tests/DB11_OWNER_USER_MANAGEMENT_INTEGRATION.sql`
- `test/features/owner/owner_user_management_widget_test.dart`

Rollback integration tested: authorized Owner invite/role state, rejected unknown actor, rejected Owner/super admin grant, immutable audit and service-role wrapper execution. Tests create no permanent users and send no emails.
