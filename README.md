# Supa Model School Management System

Private development repository for the Supa Model School Windows and Android Flutter app and its Supabase backend.

**Status:** Architecture and schema authoring in progress. **Not production ready.** No school-domain database schema has been deployed.

- Online backend: Supabase project `uebzvfzpbqqttbqyxxos` (`ap-south-1`).
- Desktop: assigned-campus SQLite/Drift offline + authenticated two-way sync.
- Android: authorized online data entry.
- Languages: English first; Pakistani Urdu optional.
- Deadline: 21-day **pilot** plan, subject to testing and financial reconciliation gates.

## Start here
- `docs/01_SRS.md` — requirements and scope.
- `docs/02_ARCHITECTURE.md` — client/server and deployment boundaries.
- `docs/03_DATA_MODEL.md` — domain entities and integrity constraints.
- `docs/04_SYNC_PROTOCOL.md` — offline sync, conflicts, idempotency.
- `docs/05_PERMISSIONS.md` — campus roles and permissions.
- `supabase/drafts/` — **review-only** SQL drafts; not deployed.
- `planning/STATUS.md` — verified work state, blockers and next tasks.

**Security:** Never commit database passwords, service-role keys or secrets. Do not enter real student/financial data until RLS, offline sync, transaction safety and restore tests pass.
