import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/offline/campus_cache_database.dart';

void main() {
  late CampusCacheDatabase db;

  setUp(() {
    db = CampusCacheDatabase.forTest(
      NativeDatabase.memory(
        setup: (sqlite) => sqlite.execute('PRAGMA foreign_keys = ON'),
      ),
    );
  });
  tearDown(() async => db.close());

  test('binds once to exactly one school, campus and desktop device', () async {
    await db.bindVerifiedAssignment(
      schoolId: 'school-a', campusId: 'campus-a', deviceId: 'device-1',
    );
    expect(await db.isBoundTo(
      schoolId: 'school-a', campusId: 'campus-a', deviceId: 'device-1',
    ), isTrue);
    await db.bindVerifiedAssignment(
      schoolId: 'school-a', campusId: 'campus-a', deviceId: 'device-1',
    );
    await expectLater(
      db.bindVerifiedAssignment(
        schoolId: 'school-a', campusId: 'campus-b', deviceId: 'device-2',
      ),
      throwsStateError,
    );
  });

  test('rejects unbound, wrong-campus and mismatched student writes', () async {
    await expectLater(
      db.customStatement(
        'INSERT INTO local_students '
        '(id,school_id,campus_id,registration_no,full_name,updated_at_ms) '
        "VALUES ('s','a','b','T-1','Example Child',1)",
      ),
      throwsA(isA<Exception>()),
    );
    await db.bindVerifiedAssignment(
      schoolId: 'school-a', campusId: 'campus-a', deviceId: 'device-1',
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO local_students '
        '(id,school_id,campus_id,registration_no,full_name,updated_at_ms) '
        "VALUES ('s','school-a','campus-b','T-1','Example Child',1)",
      ),
      throwsA(isA<Exception>()),
    );
    await db.customStatement(
      'INSERT INTO local_students '
      '(id,school_id,campus_id,registration_no,full_name,updated_at_ms) '
      "VALUES ('s','school-a','campus-a','T-1','Example Child',1)",
    );
    await expectLater(
      db.customStatement(
        'INSERT INTO local_students '
        '(id,school_id,campus_id,registration_no,full_name,updated_at_ms) '
        "VALUES ('s2','school-a','campus-a','t-1','Other Child',1)",
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('cannot mutate campus identity after dependent data is present', () async {
    await db.bindVerifiedAssignment(
      schoolId: 'school-a', campusId: 'campus-a', deviceId: 'device-1',
    );
    await db.customStatement(
      'INSERT INTO local_students '
      '(id,school_id,campus_id,registration_no,full_name,updated_at_ms) '
      "VALUES ('s','school-a','campus-a','T-1','Example Child',1)",
    );
    await expectLater(
      db.customStatement(
        "UPDATE local_campus_binding SET campus_id='campus-b' WHERE singleton=1",
      ),
      throwsA(isA<Exception>()),
    );
    expect(await db.isBoundTo(
      schoolId: 'school-a', campusId: 'campus-a', deviceId: 'device-1',
    ), isTrue);
  });

  test('v2 schema has 13 tables and foreign keys enabled', () async {
    final flags = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(flags.read<int>('foreign_keys'), 1);

    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name LIKE 'local_%'",
    ).get();
    expect(rows, hasLength(13));
  });
}
