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