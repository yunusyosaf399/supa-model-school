import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/offline/campus_cache_database.dart';
import 'package:supa_model_school/offline/offline_outbox_repository.dart';

void main() {
  late CampusCacheDatabase db;
  late OfflineOutboxRepository outbox;
  var now = 100000;
  var tokens = 0;

  String nextId() {
    tokens += 1;
    final suffix = tokens.toString().padLeft(12, '0');
    return 'aaaaaaaa-aaaa-4aaa-8aaa-' + suffix;
  }

  const school = 'test-school';
  const campus = 'campus-a';
  const device = 'device-main';
  const year = 'year-2026';
  const op1 = '11111111-1111-4111-8111-111111111111';
  const op2 = '22222222-2222-4222-8222-222222222222';

  OfflineAdmissionDraftWrite draft({
    String op = op1, String? applicationId, String name = 'Fictional Student',
    String campusId = campus, String yearId = year,
  }) => OfflineAdmissionDraftWrite(
    schoolId: school, campusId: campusId, deviceId: device,
    academicYearId: yearId, applicantName: name,
    localApplicationId: applicationId, operationId: op,
    dateOfBirth: '2016-05-10',
  );

  Future<int> count(String table) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS n FROM ' + table,
    ).getSingle();
    return row.read<int>('n');
  }

  setUp(() async {
    now = 100000;
    tokens = 0;
    db = CampusCacheDatabase.forTest(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
      ),
    );
    await db.bindVerifiedAssignment(
      schoolId: school, campusId: campus, deviceId: device,
    );
    await db.customStatement(
      'INSERT INTO local_academic_years '
      '(id,school_id,campus_id,label,starts_on,ends_on,is_active) '
      "VALUES ('year-2026','test-school','campus-a','2026-2027',"
      "'2026-04-01','2027-03-31',1)",
    );
    outbox = OfflineOutboxRepository(
      db, clockMs: () => now, uuidV4: nextId,
    );
  });
  tearDown(() async => db.close());

  test('stores draft, operation and queued event in ONE transaction', () async {
    final result = await outbox.queueAdmissionDraft(draft());
    expect(result.operationId, op1);
    expect(result.localApplicationId, op1);
    expect(result.localRevision, 1);
    expect(await count('local_admissions'), 1);
    expect(await count('local_outbox_operations'), 1);
    expect(await count('local_outbox_events'), 1);
    expect(await outbox.outstandingCount(), 1);
    final row = await db.customSelect(
      'SELECT status,payload_json,locally_edited FROM local_outbox_operations '
      'JOIN local_admissions ON local_admissions.id='
      'local_outbox_operations.aggregate_id',
    ).getSingle();
    expect(row.read<String>('status'), 'pending');
    expect(row.read<String>('payload_json'), contains(op1));
    expect(row.read<int>('locally_edited'), 1);
  });

  test('idempotent UUID retry does not reapply draft or generate events',
      () async {
    await outbox.queueAdmissionDraft(draft());
    final same = await outbox.queueAdmissionDraft(draft());
    expect(same.localRevision, 1);
    expect(await count('local_outbox_operations'), 1);
    expect(await count('local_outbox_events'), 1);
    await expectLater(
      outbox.queueAdmissionDraft(draft(name: 'Different Student')),
      throwsStateError,
    );
    expect(await count('local_admissions'), 1);
  });

  test('local edit of same draft creates later causal operation', () async {
    await outbox.queueAdmissionDraft(draft());
    final changed = await outbox.queueAdmissionDraft(
      draft(op: op2, applicationId: op1, name: 'Updated Fictional Student'),
    );
    expect(changed.localRevision, 2);
    expect(await count('local_outbox_operations'), 2);
    final first = await outbox.claimNext();
    expect(first?.operationId, op1);
    expect(await outbox.claimNext(), isNull);
    await outbox.acknowledgeFromServer(
      operationId: op1, leaseToken: first!.leaseToken, serverRevision: 1,
    );
    final second = await outbox.claimNext();
    expect(second?.operationId, op2);
    expect(second?.localRevision, 2);
    expect(await outbox.outstandingCount(), 1);
  });

  test('wrong campus and invalid FK leave NO orphan outbox record',
      () async {
    await expectLater(
      outbox.queueAdmissionDraft(draft(campusId: 'campus-b')),
      throwsStateError,
    );
    await expectLater(
      outbox.queueAdmissionDraft(draft(yearId: 'not-an-existing-year')),
      throwsA(isA<Exception>()),
    );
    expect(await count('local_admissions'), 0);
    expect(await count('local_outbox_operations'), 0);
    expect(await count('local_outbox_events'), 0);
  });

  test('retry keeps operation UUID but rotates fenced lease token', () async {
    await outbox.queueAdmissionDraft(draft());
    final first = await outbox.claimNext(leaseMs: 30000);
    expect(first?.attemptCount, 1);
    expect(await outbox.claimNext(), isNull);

    // Restarting the repository cannot change the stable operation ID.
    now += 31000;
    final reopened = OfflineOutboxRepository(
      db, clockMs: () => now, uuidV4: nextId,
    );
    final reclaimed = await reopened.claimNext();
    expect(reclaimed?.operationId, first?.operationId);
    expect(reclaimed?.payloadJson, first?.payloadJson);
    expect(reclaimed?.leaseToken, isNot(first?.leaseToken));
    expect(reclaimed?.attemptCount, 2);
    await expectLater(
      reopened.acknowledgeFromServer(
        operationId: op1,
        leaseToken: first!.leaseToken,
        serverRevision: 1,
      ),
      throwsStateError,
    );
    await reopened.acknowledgeFromServer(
      operationId: op1,
      leaseToken: reclaimed!.leaseToken,
      serverRevision: 1,
    );
    expect(await reopened.outstandingCount(), 0);
    expect(await count('local_outbox_operations'), 1);
    expect(await count('local_outbox_events'), 4);
    final local = await db.customSelect(
      "SELECT locally_edited FROM local_admissions "
      "WHERE id='11111111-1111-4111-8111-111111111111'",
    ).get(); // Dirty bit intentionally retained until server sync mapping.
    expect(local.single.read<int>('locally_edited'), 1);
  });

  test('backoff blocks following operations and preserves work', () async {
    await outbox.queueAdmissionDraft(draft());
    await outbox.queueAdmissionDraft(
      draft(op: op2,applicationId: op1,name:'Revised Fictional Student'),
    );
    final leased = await outbox.claimNext();
    await outbox.releaseForRetry(
      operationId: op1,
      leaseToken: leased!.leaseToken,
      errorCode: 'NETWORK_TIMEOUT',
      delayMs: 5000,
    );
    expect(await outbox.claimNext(), isNull);
    now += 5001;
    final retry = await outbox.claimNext();
    expect(retry?.operationId, op1);
    await outbox.flagConflict(
      operationId: op1,
      leaseToken: retry!.leaseToken,
      errorCode: 'REVISION_CONFLICT',
    );
    expect(await outbox.claimNext(), isNull);
    expect(await outbox.outstandingCount(), 2);
    expect(await count('local_outbox_operations'), 2);
  });

  test('outbox operation survives closing and reopening a real SQLite file',
      () async {
    final folder = await Directory.systemTemp.createTemp('sms-outbox-fixture');
    final file = File(folder.path + Platform.pathSeparator + 'offline-test.db');
    CampusCacheDatabase? reopened;
    try {
      final first = CampusCacheDatabase.forTest(
        NativeDatabase(
          file,
          setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      await first.bindVerifiedAssignment(
        schoolId: school, campusId: campus, deviceId: device,
      );
      await first.customStatement(
        'INSERT INTO local_academic_years '
        '(id,school_id,campus_id,label,starts_on,ends_on,is_active) '
        "VALUES ('year-2026','test-school','campus-a','2026-2027',"
        "'2026-04-01','2027-03-31',1)",
      );
      final firstOutbox = OfflineOutboxRepository(
        first, clockMs: () => now, uuidV4: nextId,
      );
      await firstOutbox.queueAdmissionDraft(draft());
      await first.close();

      reopened = CampusCacheDatabase.forTest(
        NativeDatabase(
          file,
          setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys=ON'),
        ),
      );
      final reopenedOutbox = OfflineOutboxRepository(
        reopened, clockMs: () => now, uuidV4: nextId,
      );
      expect(await reopenedOutbox.outstandingCount(), 1);
      final op = await reopenedOutbox.claimNext();
      expect(op?.operationId, op1);
      expect(op?.attemptCount, 1);
    } finally {
      await reopened?.close();
      await folder.delete(recursive: true);
    }
  });

  test('direct SQL cannot insert a second outbox operation from other campus',
      () async {
    await outbox.queueAdmissionDraft(draft());
    await expectLater(
      db.customStatement(
        'INSERT INTO local_outbox_operations '
        '(operation_id,school_id,campus_id,aggregate_type,aggregate_id,'
        'operation_type,payload_json,local_revision,created_at_ms,updated_at_ms) '
        "VALUES ('33333333-3333-4333-8333-333333333333',"
        "'test-school','campus-b','admission',"
        "'11111111-1111-4111-8111-111111111111',"
        "'admission.save_draft','{}',2,1,1)",
      ),
      throwsA(isA<Exception>()),
    );
  });
}
