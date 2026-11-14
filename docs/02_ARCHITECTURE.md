# Architecture — draft

## Clients
- Flutter Windows (assigned campus offline SQLite via Drift; two-way outbox/inbox synchronization).
- Flutter Android (authenticated online Supabase entry; no mobile offline editing in pilot).
- Cloud PostgreSQL is authoritative for confirmed records.
- Device assignment cannot change offline. Other campus records queried online by authorized users are NOT copied to the assigned-campus local store.

## Boundaries
UI -> feature repositories -> application use cases -> local Drift / cloud Supabase.
Financial business operations and campus authorization are validated on the server. Never trust client-calculated amounts, roles or approval flags.

## Modules
foundation, auth, students, admissions, fees, attendance, employees, payroll, finance, reporting, approval, sync, backup, documents, canteen, uniforms, vehicles.

## Repository policy
Supabase SQL/functions/bucket definitions live under supabase/. Draft SQL lives under supabase/drafts/ and is not auto-deployed. Use CLI-generated, versioned migrations only after testing. No secrets in source control.

## Dependencies
Foundation + auth/RLS -> students -> admissions -> fees -> receipts -> cashbook -> approvals -> consolidated reporting.
Sync metadata and idempotency must be built with the FIRST offline financial vertical slice, not left until the final week.