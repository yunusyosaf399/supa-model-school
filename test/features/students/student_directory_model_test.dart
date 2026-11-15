import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/students/models/student_directory.dart';

void main() {
  const fixture = StudentDirectoryProjection(
    authorizedCampusIds: {'allowed'},
    records: [
      StudentSummary(
        id: 'a1', registrationNo: 'TEST-001', fullName: 'Example Alpha',
        campusId: 'allowed', campusName: 'Permitted Campus',
        classId: 'grade-1', className: 'Grade 1', sectionName: 'A',
        academicYear: '2026–2027', status: StudentStatus.active,
      ),
      StudentSummary(
        id: 'a2', registrationNo: 'TEST-002', fullName: 'Example Beta',
        campusId: 'allowed', campusName: 'Permitted Campus',
        classId: 'grade-5', className: 'Grade 5', sectionName: 'B',
        academicYear: '2026–2027', status: StudentStatus.inactive,
      ),
      StudentSummary(
        id: 'b1', registrationNo: 'SECRET-001', fullName: 'Hidden Record',
        campusId: 'forbidden', campusName: 'Forbidden Campus',
        classId: 'grade-1', className: 'Grade 1', sectionName: 'A',
        academicYear: '2026–2027', status: StudentStatus.active,
      ),
    ],
  );

  test('only authorized campus records can enter visible results', () {
    final allowed = fixture.authorizedRecords;
    expect(allowed, hasLength(2));
    expect(allowed.any((s) => s.campusId == 'forbidden'), isFalse);
    expect(fixture.campuses.keys, ['allowed']);
    expect(fixture.classesForCampus(null).keys, containsAll(['grade-1', 'grade-5']));
  });

  test('unauthorized campus selector never reveals hidden records', () {
    final results = fixture.filter(const StudentDirectoryFilters(
      campusId: 'forbidden',
    ));
    expect(results, isEmpty);
    expect(fixture.classesForCampus('forbidden'), isEmpty);
  });

  test('search is case insensitive for registration and name', () {
    expect(fixture.filter(const StudentDirectoryFilters(
      searchText: '  TEST-002 ',
    )).single.fullName, 'Example Beta');

    expect(fixture.filter(const StudentDirectoryFilters(
      searchText: 'alpha',
    )).single.registrationNo, 'TEST-001');

    expect(fixture.filter(const StudentDirectoryFilters(
      searchText: 'hidden',
    )), isEmpty);
  });

  test('class and status combinations filter accurately', () {
    final results = fixture.filter(const StudentDirectoryFilters(
      classId: 'grade-5',
      status: StudentStatus.inactive,
    ));
    expect(results.map((s) => s.registrationNo), ['TEST-002']);
    expect(fixture.filter(const StudentDirectoryFilters(
      classId: 'grade-5',
      status: StudentStatus.active,
    )), isEmpty);
  });

  test('demo records are only from one fictional campus', () {
    final records = StudentDirectoryDemo.projection.authorizedRecords;
    expect(records, hasLength(4));
    expect(records.every((s) =>
      s.campusId == StudentDirectoryDemo.campusId), isTrue);
    expect(records.every((s) =>
      s.registrationNo.startsWith('DEMO-')), isTrue);
  });
}
