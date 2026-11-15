# D04-T02 — Durable local offline outbox and operation IDs

**Status: source implementation and structural review complete; Dart/SQLite runtime and crash-recovery tests have NOT run here.**

This is a **Windows assigned-campus, offline-only** local queue. Nothing is sent over the network yet. No real student records may enter this database until local database encryption, verified device/offline authorization (including expiry and revocation), backups and RLS integration have been implemented.

## Source files
- `lib/offline/schema/operation_outbox.drift` — two v2 SQLite tables, three supporting indexes and four immutable/audit triggers
- `lib/offline/offline_outbox_repository.dart` — transactional local queue and retry transitions
- `lib/offline/campus_cache_database.dart` — both Drift schemas, version 2 and non-destructive v1-to-v2 upgrade, foreign keys and WAL synchronous FULL
- `scripts/test_local_drift_schema_sqlite.py` — combined 13-table SQLite DDL and negative constraint tests
- `test/offline/offline_outbox_repository_test.dart` — atomicity, idempotency, ordering, lease, conflict and SQLite file-reopen tests
- `test/offline/campus_cache_database_test.dart` — updated for 13 tables
- `scripts/check_offline_outbox_source.py` — static guardrails

## Tables and durability

| Table | Purpose |
| --- | --- |
| `local_outbox_operations` | Persistent ordered operation UUID, original JSON payload, campus/aggregate identity, cloud/local revision, attempt count, lease, retry and server acknowledgment |
| `local_outbox_events` | Append-only queued/claimed/released/acked/conflict audit history without student names |

The first 11 tables remain from D04-T01; these two make **13 total**. Outbox records have composite foreign keys to the pinned campus and local admission; events also reference the operation.

Each operation has a UUIDv4. Repeating an IDENTICAL request with the same UUID returns its original local result without incrementing the revision; reusing a UUID with different content fails. A new UUID represents a genuinely new edit.

The repository writes the admission draft, outbox row and queued audit event inside the SAME Drift transaction. If any step fails (including FK mismatch), everything rolls back.

## State machine and retry behavior

`pending` → `sending` → `acked`

- Temporary network failure: `sending` → `pending` with retry delay
- Conflict: `sending` → `conflict`, preserving the original operation
- Oldest unacknowledged operation is always processed first. An unexpired lease, delayed retry or conflict **blocks** following work to preserve causal ordering.
- Once a lease expires, it can be reclaimed with a different lease token but the SAME operation UUID and payload; stale lease responses fail.
- Acknowledgment does NOT delete the original operation or its history.
- SQLite triggers forbid changing the original envelope and forbid deleting operations/updating or deleting audit events.
- `acknowledgeFromServer` must only be called by the future authenticated transport after matching an actual verified server response to this operation ID. This task does not implement that transport.
- Cloud revision, cloud application ID remapping, and the local dirty flag are NOT reconciled here; D04-T03 owns that work.

## Privacy and offline authorization

A campus foreign-key restriction is NOT authentication, authorization or encryption. The Windows client must verify school, campus, device, user session and offline-license expiry before accessing this file. That is NOT implemented yet.

Payload JSON may contain child data; normal SQLite is not encrypted. **No real student PII** may be stored until encrypted storage, protected key management, authorized offline sessions and backup/recovery are tested. WAL backups must contain uncheckpointed operations or use a consistent SQLite snapshot; copying just the .db file is unsafe.

Only `admission.save_draft` operation types are supported. NO offline fee, cash or salary payment operations are available.

## Local test checklist (laptop later)

1. Checkout branch `db/d04-local-drift-schema` and run `flutter doctor -v`.
2. Run `flutter pub get` and `dart run build_runner build --delete-conflicting-outputs`.
3. Run `python scripts/test_local_drift_schema_sqlite.py` and `python scripts/check_offline_outbox_source.py`.
4. Run `flutter analyze` and `flutter test test/offline/`.
5. Test v1-to-v2 upgrade on an isolated populated v1 SQLite file: confirm original campus/admission records survive and three outbox indexes plus four triggers exist.
6. Test leased operation crash/restart, repeated UUID, stale token, delayed retry, conflict and concurrent workers.
7. Review actual Windows file/WAL backup and encryption approach before enabling any real pupil data.
8. Generate and commit compatible `pubspec.lock` and Drift generated artifacts after verifying package versions and schema snapshot.

## Completion boundary

- [x] Outbox schema, indices and immutable-audit triggers written
- [x] Transactional v1-to-v2 migration source written (non-destructive)
- [x] Local draft + outbox written in one transaction (code)
- [x] UUID idempotency, ordering, retry/lease, acknowledgment and conflict transitions (code)
- [x] SQLite and Dart tests authored
- [ ] Actual SQLite tests executed and passed
- [ ] Drift generated code compiled and Flutter tests passed
- [ ] v1-to-v2 migration tested with previously populated SQLite file
- [ ] Encrypted storage, auth expiry, backups and real server sync validated

**D04-T02 is complete for code authoring, not verified production behavior.**

## Subsequent tasks
D04-T03 idempotent Supabase ingestion and cloud ID/receipt mapping; D04-T04 durable cloud change feed and cursor; D04-T05 complete offline vertical slice on registered Windows hardware. No Supabase cloud schema has been changed.
