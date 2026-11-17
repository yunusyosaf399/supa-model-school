# DB10 — Owner setup RPC bridge (first implementation increment)

## Purpose
The deployed DB01/DB02 baseline already contains three atomic, Owner-verified
`app_private` operations. Rather than duplicate their business logic, DB10
adds narrow public PostgREST RPC bridges. This is an **implementation draft**;
no SQL has been applied to the live project by this PR.

## Endpoints
- `db10_owner_complete_initial_setup`: one-time school/campus configuration and
  active academic year, with explicit optimistic-revision preconditions.
- `db10_owner_create_class_with_sections`: atomically creates a class and its
  distinct sections for the active year at one campus.
- `db10_owner_dashboard_snapshot`: Owner-only overview; a demo flag must remain
  visibly different from live data.

Invoke using Supabase's authenticated Dart client:
`supabase.rpc('db10_owner_dashboard_snapshot', params: {'p_school_id': id, 'p_campus_id': campusId})`

**Do not call the RPC without a signed-in verified Owner**. Public wrapper
permissions allow authenticated users to invoke the function, but the
underlying DB01/DB02 function independently validates the verified and active
Owner role for the supplied school. The wrapper is SECURITY INVOKER, and
PostgreSQL PUBLIC/anon execution is revoked.

## Testing required before enabling the UI
1. Run a disposable local PostgreSQL stack using the exact DB01–DB09 migrations.
2. Apply the SQL from `supabase/drafts/DB10_OWNER_SETUP_RPC.sql` in a transaction;
   check parser/function resolution, then run `supabase/tests/DB10_RPC_PERMISSIONS.sql`.
3. Test with a verified Owner: expected setup succeeds once and creates one
   academic year with audit record; stale revisions fail; duplicate class fails.
4. Test other school/campus Owner, staff, unverified, anonymous and revoked
   users: all fail without producing rows.
5. Verify the returned dashboard is accurately marked `is_demo` before setup;
   after setup its records and counts come from real authorized school data.
6. Verify no table GRANTs, service keys or direct client writes are added.
7. Generate a real CLI migration and deploy after review; verify live function
   privileges and PostgREST availability, then wire Flutter forms.

**Explicitly excluded:** admission submission/approval, fees/payment,
SQLite sync and mobile offline entry. These need additional transaction and
authorization implementations; no live business records should be inserted.
