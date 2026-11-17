import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/students/data/student_directory_repository.dart';
import 'package:supa_model_school/features/students/models/student_directory.dart';
import 'package:supa_model_school/features/students/presentation/student_directory_page.dart';

class FakeStudents implements StudentDirectoryRepository {
  FakeStudents({this.fail = false});
  final bool fail;
  final calls = <String>[];

  @override
  Future<StudentDirectoryProjection> load({
    required String schoolId,
    required String campusId,
  }) async {
    calls.add('$schoolId/$campusId');
    if (fail) throw StateError('network disconnected');
    return StudentDirectoryProjection(
      authorizedCampusIds: {campusId},
      records: [
        StudentSummary(
          id: 'student-1',
          registrationNo: 'TEST-2026-0001',
          fullName: 'TEST Student A',
          campusId: campusId,
          campusName: 'Main Campus',
          classId: 'class-1',
          className: 'Grade 1',
          sectionName: 'A',
          academicYear: '2026-2027',
          status: StudentStatus.active,
        ),
      ],
    );
  }
}

const owner = OwnerAccess(
  userId: 'owner-1',
  displayName: 'Owner',
  schoolId: 'school-1',
  schoolName: 'Supa Model School',
  setupComplete: true,
  campuses: [OwnerCampus(id: 'campus-1', name: 'Main Campus')],
);

Widget studentPage(FakeStudents repo) => MaterialApp(
  home: Scaffold(
    body: StudentDirectoryPage(
      owner: owner,
      selectedCampusId: 'campus-1',
      repository: repo,
      onNewAdmission: () {},
    ),
  ),
);

void main() {
  testWidgets('authenticated student directory uses scoped server data', (tester) async {
    final repo = FakeStudents();
    await tester.pumpWidget(studentPage(repo));
    await tester.pumpAndSettle();
    expect(repo.calls, ['school-1/campus-1']);
    expect(find.text('TEST Student A'), findsOneWidget);
    expect(find.textContaining('TEST-2026-0001'), findsWidgets);
    expect(find.textContaining('DEMO MODE'), findsNothing);
    expect(find.text('Example Student Alpha'), findsNothing);
  });

  testWidgets('failed live fetch never falls back to demo students', (tester) async {
    final repo = FakeStudents(fail: true);
    await tester.pumpWidget(studentPage(repo));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load authorized students'), findsOneWidget);
    expect(find.text('Example Student Alpha'), findsNothing);
    expect(find.text('TEST Student A'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}
