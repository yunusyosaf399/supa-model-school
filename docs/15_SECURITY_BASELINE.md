# Security baseline

- PostgreSQL RLS must protect every table in exposed schema `public`; authenticated alone does not confer access to every row.
- User role/campus membership cannot be self-assigned. No user metadata is trusted for authorization; permissions stored in server-protected tables.
- Secret/service role keys never embedded in Flutter, GitHub or logs.
- Security-definer functions are exceptional, non-exposed, use explicit `auth.uid()` checks, fully qualified relations, fixed search_path, restrictive EXECUTE grants and manual review.
- New school data tables must be denied to authenticated users by default until explicit policies are reviewed.
- Financial approvals and idempotency enforced server-side in atomic operations.
- Offline device assignment, session expiry, encrypted/protected SQLite/backups and remote revocation strategy required.
- Separate Storage access policies from database RLS; backups of database do not include Storage objects.
- Use realistic test school/campus/users and prove unauthorized access fails; never test with real children data.