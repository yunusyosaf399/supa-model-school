# Admission workflow migration/testing order

**Work-in-review SQL. No file in this directory is a Supabase versioned migration.**

Read the Supabase CLI help on the laptop, then generate the official migration names with `supabase migration new ...`. Do NOT invent timestamps manually.

Run drafts in this dependency order against a disposable **local** Supabase database:

1. `supabase/drafts/DB01_foundation.sql`
2. `supabase/drafts/DB02_admissions.sql`
3. `supabase/drafts/DB02_WORKFLOW_SCHEMA.sql`
4. `supabase/drafts/DB02_ADMISSION_OPERATIONS.sql`

Some drafts contain `BEGIN`/`COMMIT`; inspect migration transaction handling in the installed Supabase CLI before testing/resetting.

Use fictional Auth identities. Run the schema integrity tests first, then the [40-case acceptance matrix](../tests/ADMISSION_WORKFLOW_ACCEPTANCE.md). Verify true role isolation using fresh Auth sessions, not only SQL statements run as a database superuser.

**Caution:** `app_private` is not an exposed Data API schema. The SQL functions are intended to be called from the authenticated, privileged Edge function using a protected DB connection after independent Auth verification. They are NOT public RPC endpoints.

The flow is not ready for merging or cloud deployment until test results, privileged-function audits, storage access protections, and concurrent retry/idempotency checks pass.
