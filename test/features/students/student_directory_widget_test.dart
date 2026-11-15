import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/students/models/student_directory.dart';
import 'package:supa_model_school/features/students/presentation/student_directory_page.dart';

void main() {
  testWidgets('mobile directory has sample banner and search field',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentDirectoryPage(onNewAdmission: () {}),
      ),
    ));

    expect(find.text('Student Directory'), findsOneWidget);
    expect(find.textContaining('fictional students only'), findsOneWidget);
    expect(find.byKey(const Key('student-directory-search')), findsOneWidget);
    expect(find.textContaining('4 of 4 sample students'), findsOneWidget);
  });

  testWidgets('registration search filters and clear resets result count',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentDirectoryPage(onNewAdmission: () {}),
      ),
    ));

    await tester.enterText(
      find.byKey(const Key('student-directory-search')),
      'demo-002',
    );
    await tester.pump();
    expect(find.textContaining('1 of 4 sample students'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('student-directory-search')),
      'not found anywhere',
    );
    await tester.pump();
    expect(find.byKey(const Key('student-empty-results')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('clear-student-filters')));
    await tester.tap(find.byKey(const Key('clear-student-filters')));
    await tester.pump();
    expect(find.textContaining('4 of 4 sample students'), findsOneWidget);
  });

  testWidgets('profile entry opens read-only fictional student preview',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentDirectoryPage(onNewAdmission: () {}),
      ),
    ));

    final target = find.byKey(const Key('student-card-demo-student-001'));
    await tester.scrollUntilVisible(target, 180,
        scrollable: find.byKey(const Key('student-directory')));
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(find.text('Student Profile (preview)'), findsOneWidget);
    expect(find.byKey(const Key('student-preview-name')), findsOneWidget);
    expect(find.textContaining('FICTIONAL PREVIEW'), findsOneWidget);
  });

  testWidgets('wide layout uses a horizontally scrollable data table',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentDirectoryPage(onNewAdmission: () {}),
      ),
    ));

    expect(find.byKey(const Key('student-desktop-table')), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    expect(find.byKey(const Key('view-student-demo-student-001')),
        findsOneWidget);
  });

  testWidgets('unauthorized records are not shown in UI search or filters',
      (tester) async {
    const fixture = StudentDirectoryProjection(
      authorizedCampusIds: {'a'},
      records: [
        StudentSummary(
          id: 'a', registrationNo: 'DEMO-A', fullName: 'Allowed Example',
          campusId: 'a', campusName: 'Campus A',
          classId: '1', className: 'Grade 1', sectionName: 'A',
          academicYear: '2026–2027', status: StudentStatus.active,
        ),
        StudentSummary(
          id: 'b', registrationNo: 'DEMO-B', fullName: 'Forbidden Example',
          campusId: 'b', campusName: 'Campus B',
          classId: '1', className: 'Grade 1', sectionName: 'A',
          academicYear: '2026–2027', status: StudentStatus.active,
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StudentDirectoryPage(
          onNewAdmission: () {},
          projection: fixture,
        ),
      ),
    ));

    expect(find.textContaining('1 of 1 sample students'), findsOneWidget);
    expect(find.text('Forbidden Example'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('student-directory-search')),
      'forbidden',
    );
    await tester.pump();
    expect(find.byKey(const Key('student-empty-results')), findsOneWidget);
    expect(find.text('Campus B'), findsNothing);
  });
}
