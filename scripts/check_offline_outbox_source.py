#!/usr/bin/env python3
"""D04-T02 static source review; NOT Drift compilation or SQLite execution."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
outbox = (root / 'lib/offline/schema/operation_outbox.drift').read_text()
base = (root / 'lib/offline/schema/campus_cache.drift').read_text()
database = (root / 'lib/offline/campus_cache_database.dart').read_text()
repository = (root / 'lib/offline/offline_outbox_repository.dart').read_text()
sqlite_tests = (root / 'scripts/test_local_drift_schema_sqlite.py').read_text()
dart_tests = (root / 'test/offline/offline_outbox_repository_test.dart').read_text()

assert len(re.findall(r'(?m)^CREATE TABLE ', base)) == 11
assert set(re.findall(r'(?m)^CREATE TABLE (\w+)', outbox)) == {
    'local_outbox_operations', 'local_outbox_events'
}
assert len(re.findall(r'(?m)^CREATE (?:UNIQUE )?INDEX ', outbox)) == 3
assert set(re.findall(r'(?m)^CREATE TRIGGER (\w+)', outbox)) == {
    'local_outbox_envelope_immutable',
    'local_outbox_operations_no_delete',
    'local_outbox_events_no_update',
    'local_outbox_events_no_delete',
}
assert 'REFERENCES local_campus_binding (school_id,campus_id)' in outbox
assert 'REFERENCES local_admissions (id,school_id,campus_id)' in outbox
assert 'UNIQUE (aggregate_type,aggregate_id,local_revision)' in outbox
assert 'status IN (\'pending\',\'sending\',\'acked\',\'conflict\')' in outbox
assert "'schema/operation_outbox.drift'" in database
assert 'schemaVersion => 2' in database
assert 'if (from == 1 && to == 2)' in database
assert 'migrator.createTable(localOutboxOperations)' in database
assert 'migrator.createTable(localOutboxEvents)' in database
assert database.count('CREATE TRIGGER') == 4
assert 'PRAGMA synchronous = FULL' in database
assert 'Platform.isWindows' in database

for method in ('queueAdmissionDraft','claimNext','releaseForRetry',
               'acknowledgeFromServer','flagConflict','outstandingCount'):
    assert method in repository, method
assert 'return db.transaction(() async {' in repository
assert repository.count('db.transaction(() async {') >= 5
assert 'Random.secure()' in repository
assert 'Operation UUID replayed with different contents' in repository
assert "WHERE status<>'acked'" in repository
assert 'ORDER BY sequence_no LIMIT 1' in repository
assert 'lease_until_ms' in repository and 'leaseToken' in repository
assert 'readNullable' in repository
for forbidden in ('SUPABASE_DB_URL','service_role','http.post('):
    assert forbidden not in repository, forbidden

assert 'OUTBOX_SQL.read_text' in sqlite_tests
assert 'local_outbox_events_no_update' in outbox
assert 'outbox operation survives' in dart_tests.lower()
assert 'flagConflict' in dart_tests
print('STATIC PASS: 13 SQL tables, 3 outbox indexes, 4 audit triggers, v2 migration source, outbox transaction state-machine and test sources.')
print('NOT VERIFIED: real SQLite execution, Flutter build, v1 migration, protected storage, authenticated ingest, or sync.')
