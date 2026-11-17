# Backup and disaster recovery

Owner configures destinations: protected local folder, optional external drive, cloud encrypted snapshot path. Daily consistent SQLite snapshots should include a manifest with campus ID, schema version, sync cursor, checksum, pending outbox count and timestamp.

Recovery of replacement desktop:
1. Authenticate and validate registered device/campus.
2. Load authoritative permitted cloud snapshot.
3. Restore required Storage documents separately.
4. Inspect independent local/external backups for legitimate unsynced operations.
5. Reconcile backups and outbox without overwriting newer confirmed cloud records.
6. Verify checksums, ledger balance and conflicts; issue recovery report.

Unuploaded records existing solely on a lost PC are unrecoverable without a separate backup. Supabase DB backups do not include Storage file bytes. Backup/restore paths require drills before real data.
## DB09 backup/restore schema design (2026-11-17; NOT DEPLOYED)
- `db09_backup_destinations` captures Owner-selected protected local,
  external drive or encrypted cloud destination metadata (not secrets).
- `db09_backup_manifests` records campus, source device, schema version,
  last cloud cursor, SHA256, pending outbox/conflict counts and encryption.
  `db09_backup_artifacts` links encrypted SQLite/outbox/Storage files.
- Restoration requires online school/campus authorization. First reconstruct
  latest authoritative cloud state, then verify and separately replay
  legitimate unsynced operations from surviving backups without overwriting
  newer cloud records. Storage file bytes need separate backup/restore.
- `db09_restore_sessions` and `db09_restore_check_events` preserve
  restore approval and verification steps. Actual encryption/key handling,
  backup scheduler and restore drills are NOT implemented.
- Data only ever stored on destroyed offline PC without backups is lost.
See `docs/38_DB09_SYNC_BACKUP_REPORTING_DESIGN.md`.
