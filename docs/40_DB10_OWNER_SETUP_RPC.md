# DB10 — Existing Owner RPC Integration Gate (2026-11-17)

## Reconciliation: NO additional DB10 wrapper functions needed

During DB10 integration review we verified three existing, deployed, authenticated, security-invoker RPCs:

| Existing public RPC | Backing private operation | Flutter status |
| --- | --- | --- |
| `owner_complete_initial_setup` | `app_private.complete_owner_initial_setup` | Owner onboarding service already available |
| `owner_create_class_with_sections` | `app_private.owner_create_class_with_sections` | Academic structure repository already available |
| `owner_dashboard_snapshot` | `app_private.owner_dashboard_snapshot` | Dashboard repository already wired |

The earlier proposed `db10_owner_*` wrapper names duplicated this API. We removed that source before migration/deployment. **Do not deploy duplicate DB10 RPC wrappers.** Keep established endpoint names and wire any missing UI routes to them.

## Executed rollback-only integration

`supabase/tests/DB10_EXISTING_OWNER_RPC_INTEGRATION.sql` was run against the connected Supa Model School project in a single BEGIN/ROLLBACK session.

Confirmed:
- exactly the 3 expected existing public RPCs, SECURITY INVOKER and inaccessible to anon;
- verified bootstrap Owner's dashboard reports `is_demo=true` before setup;
- setup creates exactly one active academic year and an auditable setup event;
- a stale setup revision is rejected;
- class + two sections creates an academic structure audit event;
- case-insensitive duplicate class creation is rejected;
- Owner's dashboard switches to `is_demo=false` after temporary setup;
- fake authenticated caller is rejected for setup, class creation, and dashboard.

The existing placeholder currency is `XXX`. The test provides valid `PKR` and `Asia/Karachi` for its **temporary** Owner setup payload. School settings, academic years, classes and audit rows are unchanged after ROLLBACK.

## Remaining test gates

- Cross-school/cross-campus, revoked Owner/staff and expired-authenticated-session tests with disposable identities.
- End-to-end PostgREST/Flutter RPC invocation and UI acceptance on Windows and Android.
- GitHub CI runner test repeatability.
- Admissions and financial operations (and desktop offline sync) are not implemented here.

## Rollout state

**No new Supabase DDL or migration required for these Owner RPCs.** Do not modify live school setup or insert real financial/student data as part of this task. Future integration work should use the existing three RPCs and their established Dart repositories. 
