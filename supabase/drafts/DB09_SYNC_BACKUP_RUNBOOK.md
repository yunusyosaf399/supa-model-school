# DB09 Local-Only Sync and Recovery Runbook

No hosted schema deployment and no Flutter code. Test the DB01–DB09 source chain in a disposable local Supabase/PostgreSQL environment. Create fictional `sms-adm-admin-a@example.invalid` Auth user first. Review unmerged D04-T03/T04 ingest/change-feed drafts for overlap; do NOT apply both change-feed systems.

```powershell
python supabase/tests/check_db09_schema.py
psql -X -v ON_ERROR_STOP=1 -f supabase/tests/DB09_SYNC_BACKUP_INTEGRATION.sql
```

Fixture is fictional BEGIN/ROLLBACK only. **NOT EXECUTED**.

### Mandatory real acceptance (not implemented by DDL)

1. Two campus devices: campus A offline cache must never contain campus B pupil/fee/attendance/payroll rows. Device cannot change campus while offline.
2. Current server user role, device authorization, expired/granted offline permission, session revocation, request hash and expected revision verified per POST and page of PULL.
3. Two concurrent transactions allocate commit-ordered cloud cursors; rollback does not expose gaps that block clients; page cursors advance only when client has fully committed the corresponding local SQLite batch.
4. Same operation UUID + same hash returns identical receipt after lost network ACK; changed hash conflicts. Finance and payroll remain online-only approvals; no double receipt or advance.
5. Conflict source preserves original both sides. Never last-write-wins for fees, payments, admission finalization or stock moves. Authorized resolution creates new revision and audit.
6. Device revoked mid-sync stops both upload and download. Key rotation and encrypted local SQLite storage are tested before personal child data.
7. Backup snapshots use consistent SQLite snapshot API and contain campus, cursor, outbox and checksum manifest; cloud and external backup files are separately encrypted.
8. Recovery on replacement desktop loads latest authorized Supabase state first, then validates/replays pending operations from surviving backup. Restore Storage objects separately. A lost sole local outbox cannot be recovered.
9. Cash closing blocked while relevant offline outbox/conflict/approval pending; sync status cannot be forged by client-supplied counts.
10. Owner/report projections obey campus permissions and source domain accounting; no demo numbers appear as real metrics; no direct authenticated query on private sync tables.
11. Run actual PostgreSQL DDL parser, dependency order, indexes, RLS, security advisor, concurrency, load tests and realistic offline multi-day reconnection before migration approval.

**Design count: 0 full schema domains left to author; 7 domains DB03–DB09 still require review, local tests, migration work and deployment.**
