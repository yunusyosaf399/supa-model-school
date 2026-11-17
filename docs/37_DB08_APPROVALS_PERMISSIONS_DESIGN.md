# DB08 — Permissions, Approval Workflows, Audit and Notifications

**SQL source design only — not a production migration or deployed feature.**
Branch `db/db08-approvals-permissions-audit-20261117` stacked on DB07.

## Domain coverage: 18 tables

The SQL draft `supabase/drafts/DB08_APPROVALS_PERMISSIONS_AUDIT_SCHEMA.sql` defines:
- `db08_roles`, `db08_permissions`, `db08_role_grants`, `db08_user_overrides`, `db08_role_audit`: school role/permission catalog, time-bounded campus overrides and immutable role change audit.
- `db08_approval_policies`, `db08_approval_steps`, `db08_workflow_subjects`, `db08_approval_requests`, `db08_approval_sources`, `db08_approval_delegations`, `db08_approval_decisions`: scoped, versioned Owner-approved policies, amount thresholds, ordered roles/steps, typed school/campus source keys, explicit delegation, immutable decisions and self-approval protection.
- `db08_audit_events`, `db08_document_templates`, `db08_notification_messages`, `db08_notification_events`, `db08_user_shortcuts`, `db08_operation_receipts`: immutable general audit, English-first/Urdu-ready document layouts, notification delivery/read events, personal shortcuts and exact-request replay receipts.

## Roles

Existing DB01 `user_roles` whitelist is expanded to Owner, Super Admin, Principal, Vice Principal, Admin, Accountant, HR, Teacher, Coordinator, Librarian, Transport Manager, Driver, Nurse, Store Keeper, Security Guard, Parent and Attendance Staff.

Existing DB01 school-wide Owner/Super Admin and campus-scoped all-other-role rules remain. New roles must be seeded and audited in a reviewed migration. **Do not grant staff access simply by adding a code to the CHECK**. Effective current campus user role, time-bounded authorization and active employee/teacher assignment must be checked by trusted server operations, not JWT user_metadata or Flutter UI.

## Approval model

1. School Owner configures action, campus or school scope, policy version, amount threshold and one or more steps. The current policy is bound to each request so future policy edits cannot alter its approval history.
2. Real domain event (expense request, employee leave, attendance correction, inventory transfer, stock count) is referenced with typed composite FK matching school/campus. Other domains use a **trusted workflow subject registry** whose underlying entity must be separately validated server-side.
3. Inbound Windows offline requests may remain **local Pending Approval** until online acceptance; NO offline decision can post a cash movement, payroll, refund, school transfer or finalized approval.
4. Server validates current reviewer role and campus, correct step order, authorization/delegation validity, current policy, recipient scope, conflict revision, and checks requester is not the reviewer. DDL independently rejects exact actor=self for a recorded decision and duplicate decision per request+step.
5. Original decision/role and audit records are immutable. Subsequent correction is a new event, never silent overwrite.
6. Only an approved online server transaction may update domain business state and post to DB06 accounting, create operation receipt and audit record simultaneously.

**Not implemented by this SQL:** actual policy engine, step aggregation, cross-domain status propagation, delegated grant eligibility, permission evaluation RPC, notification sending, storage template rendering, document signing, RLS read policies.

## Security

All 18 new public tables enable RLS with **direct anon/authenticated privileges revoked**. No permissive data policies or public SECURITY DEFINER endpoint is added. Current `user_roles` remains protected by existing policies. Generic metadata must not include student medical/bank secrets or authorization data. Privacy-sensitive audit content needs retention, encryption and authorization.

## Local testing gates

- `supabase/tests/DB08_APPROVALS_INTEGRATION.sql` — fictional BEGIN/ROLLBACK with two Auth test accounts, approved expense source, self-approval/duplicate/rewrite rejection, role additions and RLS checks.
- `supabase/tests/check_db08_schema.py` — static textual checks (not execution).
- `supabase/drafts/DB08_APPROVALS_RUNBOOK.md` — concurrency, campus isolation, approvals, privacy and permission acceptance plan.

**No PostgreSQL SQL execution, campus-role RLS tests, Flutter changes or live deployment.**

Progress after DB08: DB01–DB02 baseline deployed, DB03–DB08 design sources authored but not deployed; **1 full domain (DB09) remains to design**, and **7 domains (DB03–DB09) remain undeployed**.
