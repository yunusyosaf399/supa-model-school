import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'campus_cache_database.g.dart';

/// Campus-local SQLite cache definition.
///
/// This database is for the ONE registered offline Windows desktop per campus.
/// It must NEVER open on Android or on another Windows client in production.
/// The backend must verify device assignment and offline authorization before
/// [bindVerifiedAssignment] is called. A local SQLite file is NOT an access
/// control or encryption boundary.
@DriftDatabase(include: {
  'schema/campus_cache.drift',
  'schema/operation_outbox.drift',
})
class CampusCacheDatabase extends _$CampusCacheDatabase {
  CampusCacheDatabase.forTest(QueryExecutor executor) : super(executor);

  /// Requires an already-attested device assignment and a protected location.
  ///
  /// Deliberately does not select a default DB path or open on Android.
  CampusCacheDatabase.forWindowsFile(File file)
      : super(_openWindowsFile(file));

  static QueryExecutor _openWindowsFile(File file) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Offline campus cache is Windows-only in v1.');
    }
    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        // Every native connection (including future read-isolates) must have
        // FK enforcement. Drift's beforeOpen hook verifies the pragma too.
        database.execute('PRAGMA foreign_keys = ON');
        database.execute('PRAGMA journal_mode = WAL');
        // FULL synchronous mode prioritizes durable local commits over speed.
        // Backups must include/reconcile WAL data, not copy only the .db file.
        database.execute('PRAGMA synchronous = FULL');
        database.execute('PRAGMA busy_timeout = 5000');
      },
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          final pragma = await customSelect('PRAGMA foreign_keys').getSingle();
          if (pragma.read<int>('foreign_keys') != 1) {
            throw StateError('SQLite foreign keys must be enabled.');
          }
        },
        onUpgrade: (migrator, from, to) async {
          // v1 -> v2 ONLY adds the outbox and its audit trail. Existing campus,
          // student and admission tables are preserved without data copying.
          // Keep the entire step atomic to avoid a half-migrated database if
          // the application is terminated during the upgrade.
          if (from == 1 && to == 2) {
            await transaction(() async {
              await migrator.createTable(localOutboxOperations);
              await migrator.createTable(localOutboxEvents);
              await customStatement(
                'CREATE INDEX local_outbox_status_seq_idx '
                'ON local_outbox_operations (status, sequence_no)',
              );
              await customStatement(
                'CREATE INDEX local_outbox_aggregate_seq_idx '
                'ON local_outbox_operations (aggregate_type, aggregate_id, '
                'sequence_no)',
              );
              await customStatement(
                'CREATE INDEX local_outbox_events_operation_idx '
                'ON local_outbox_events (operation_id, event_seq)',
              );
              // Match the immutable-envelope / append-only SQL triggers in
              // operation_outbox.drift for non-destructive v1->v2 upgrades.
              await customStatement(
                'CREATE TRIGGER local_outbox_envelope_immutable '
                'BEFORE UPDATE OF operation_id,school_id,campus_id,'
                'aggregate_type,aggregate_id,operation_type,payload_json,'
                'expected_cloud_revision,local_revision,created_at_ms '
                'ON local_outbox_operations BEGIN '
                "SELECT RAISE(ABORT,'Offline operation envelope is immutable'); END",
              );
              await customStatement(
                'CREATE TRIGGER local_outbox_operations_no_delete '
                'BEFORE DELETE ON local_outbox_operations BEGIN '
                "SELECT RAISE(ABORT,'Offline operation deletion requires reviewed retention'); END",
              );
              await customStatement(
                'CREATE TRIGGER local_outbox_events_no_update '
                'BEFORE UPDATE ON local_outbox_events BEGIN '
                "SELECT RAISE(ABORT,'Offline audit events are append-only'); END",
              );
              await customStatement(
                'CREATE TRIGGER local_outbox_events_no_delete '
                'BEFORE DELETE ON local_outbox_events BEGIN '
                "SELECT RAISE(ABORT,'Offline audit events are append-only'); END",
              );
            });
            return;
          }
          throw UnsupportedError(
            'Missing reviewed offline schema migration: $from -> $to',
          );
        },
      );

  /// Pin a database to the server-verified device, school and campus.
  ///
  /// IMPORTANT: This is NOT an authentication operation. The caller must
  /// validate the current user, device registration, and assigned campus
  /// with an authoritative online endpoint before invoking this method.
  ///
  /// Re-opening a bound database with a different school, campus or device
  /// fails. The DB schema also uses composite campus FKs for every replica.
  Future<void> bindVerifiedAssignment({
    required String schoolId,
    required String campusId,
    required String deviceId,
  }) async {
    if (schoolId.isEmpty || campusId.isEmpty || deviceId.isEmpty) {
      throw ArgumentError('Verified school, campus and device IDs required');
    }
    await transaction(() async {
      final rows = await customSelect(
        'SELECT school_id, campus_id, device_id '
        'FROM local_campus_binding WHERE singleton = 1',
      ).get();
      if (rows.isNotEmpty) {
        final existing = rows.single;
        final isSame = existing.read<String>('school_id') == schoolId &&
            existing.read<String>('campus_id') == campusId &&
            existing.read<String>('device_id') == deviceId;
        if (!isSame) {
          throw StateError(
            'This offline database belongs to a different verified device '
            'or campus. Never reassign or reuse it for another campus.',
          );
        }
        return;
      }

      await customStatement(
        'INSERT INTO local_campus_binding '
        '(singleton, school_id, campus_id, device_id, activated_at_ms) '
        'VALUES (1, ?, ?, ?, ?)',
        [
          schoolId,
          campusId,
          deviceId,
          DateTime.now().toUtc().millisecondsSinceEpoch,
        ],
      );
      await customStatement(
        'INSERT INTO local_replica_metadata '
        '(singleton, school_id, campus_id) VALUES (1, ?, ?)',
        [schoolId, campusId],
      );
    });
  }

  /// A read-only scope check for consumers, not a substitute for Auth/RLS.
  Future<bool> isBoundTo({
    required String schoolId,
    required String campusId,
    required String deviceId,
  }) async {
    final row = await customSelect(
      'SELECT school_id, campus_id, device_id '
      'FROM local_campus_binding WHERE singleton = 1',
    ).getSingleOrNull();
    return row != null &&
        row.read<String>('school_id') == schoolId &&
        row.read<String>('campus_id') == campusId &&
        row.read<String>('device_id') == deviceId;
  }
}
