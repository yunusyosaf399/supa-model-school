# DB09 — Offline Synchronization, Backup, Restore and Reporting

**Schema design only — NOT DEPLOYED.** Branch `db/db09-sync-backup-reporting-20261117` stacks on DB08. No Flutter/UI changes.

## Requirements

The assigned **Windows PC** can work with a campus-only SQLite replica when offline; automatic sync resumes on internet and users can choose **Sync Now**. Android is **online-only** in v1. A local draft is not an approved/posted financial fact. The server checks current authenticated user, assigned device, school, campus, role, device expiry/revocation and expected record revision for each operation and pull.

## 18 public tables

1. `db09_device_authorizations`: one registered Windows device + school/campus, offline permission, expiry and revocation
2. `db09_device_access_events`: immutable device changes
3. `db09_operation_receipts`: stable operation UUID + SHA256 payload digest and accepted/rejected/conflict/pending approval result
4. `db09_change_clocks`: per-school row-locked global cursor
5. `db09_cloud_changes`: ordered scoped upsert/delete/revocation feed, immutable
6. `db09_tombstones`: deletion markers
7. `db09_device_cursors`: reported last *locally applied* cursor, not proof of disk commit
8. `db09_sync_conflicts`: rejected stale revisions/security and business rule conflicts
9. `db09_conflict_resolutions`: immutable authorized decision
10. `db09_sync_runs`: sync run audit and counts
11. `db09_backup_destinations`: Owner-configured encrypted local/external/cloud destination metadata
12. `db09_backup_manifests`: checksum, schema version, cursor, pending outbox/conflicts and encryption flag
13. `db09_backup_artifacts`: encrypted SQLite, outbox and separate Storage-file artifact references
14. `db09_restore_sessions`: approved device replacement/restore workflow
15. `db09_restore_check_events`: immutable checksum/cloud/Storage/replay/verification steps
16. `db09_report_definitions`: predefined scoped report kind/parameters (not arbitrary SQL)
17. `db09_report_snapshots`: generated school/campus metrics with source cursor, freshness and explicit demo flag
18. `db09_device_reassign_events`: audited reassignment decisions requiring online wipe/rebootstrap

The source is `supabase/drafts/DB09_SYNC_BACKUP_REPORTING_SCHEMA.sql`.

## Correct cloud sequence and SQLite handshakes

An authenticated trusted posting transaction updates the per-school `db09_change_clocks` row before inserting each change (trigger allocates a counter while holding a lock). Competing transactions for the same school serialize their sequence allocation, so committed change rows are cursor-ordered. A bare PostgreSQL sequence would not guarantee commit order. Change events must be committed atomically with the business record updates; all changes must be emitted for relevant tables.

Client flow: (1) local edit + outbox row atomically; (2) send stable ID and hash; (3) server verifies current campus authorization and domain rules; (4) server commits operation receipt, business changes and feed events together; (5) client pulls filtered, bounded feed including tombstones; (6) SQLite applies records and cursor **in one transaction**, then acknowledges; (7) retries use same request hash and original receipt, conflicts await human review. Device revocation/campus reassignment must halt old replica operations. Offline device must not switch campus without online wipe and authorization.

The DB09 schema does **not** itself supply the authenticated ingest/pull RPC/Edge functions, encryption keys or SQLite transaction implementation. Earlier D04-T03/D04-T04 draft branches already contain different ingest/change-feed constructs. **Reconcile their names, sequences, service contracts and migration dependencies**—do not deploy duplicate feeds or treat unmerged scripts as deployed.

## Backup and replacement desktop recovery

Owner selects protected local directory, external drive and/or encrypted cloud snapshot destination. Backup manifest records the encrypted artifact checksum, schema version, campus ID, applied cloud cursor, pending outbox count and age. The Supabase database remains authoritative for **accepted** operations.

Restore process:
1. Authenticate Owner/assigned campus and authorize replacement device online.
2. Download the latest permitted **cloud state** and document references; never replace it with stale SQLite.
3. Independently verify backup/encrypted artifacts/checksums and restore Storage file bytes where available (Supabase DB backup alone does not include Storage objects).
4. Extract legitimate pending outbox from surviving encrypted local/external backups and **replay each original operation** through trusted cloud validation, never blindly write local rows on top of newer cloud data.
5. Resolve duplicates/conflicts, record immutable recovery checks and verify financial/attendance balances, completeness and authorized campus scope.

Unsynced data on a destroyed PC with no external backup **cannot be recovered**. Backup manifests alone are not backup bytes; actual backup encryption, destination permission, scheduling and restore drills are future implementation.

## Reporting

Predefined Owner/campus dashboard and fee/attendance/payroll/cashbook/inventory/transport summaries. Campus Principal may receive school-wide reports only where Owner-granted. Aggregates must use approved source events and avoid counting attendance after-break twice, fee receipt as extra revenue, salary advance as expense, or inventory procurement as COGS. `is_demo` stays explicit. No new Data API client grants or public read views in this draft.

## Security and remaining gates

All 18 new public tables have RLS enabled and anon/authenticated grants revoked. No public posting endpoints. Real authorization cannot rely solely on the user's JWT claims or campus UI filter. Private storage policies for sensitive student files and offline SQLite encryption/key management remain mandatory.

**Required before deployment:** local PostgreSQL execution + synthetic fixture, full DB08 permissions/RLS, two-session commit-order tests, reboot/lost acknowledgement, request tampering, device revocation, RLS data leaks, multi-day cursor pruning, schema upgrades and retention, backup restore, financial offline approvals and DB06 cash close tests. DB06 also needs DB07 POS/COGS typed journal integration.

**All 9 core domains now have source designs**: DB01–DB02 deployed baseline, DB03–DB09 draft/partial and **NOT deployed**. **0 core domains remain undesigned; 7 domains remain to test/integrate/deploy (DB03–DB09)**. Design completion is not implementation completion.
