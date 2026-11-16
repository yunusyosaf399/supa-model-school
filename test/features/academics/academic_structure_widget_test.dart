import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/academics/data/academic_structure_repository.dart';
import 'package:supa_model_school/features/academics/presentation/academic_structure_page.dart';

class FakeAcademicRepository implements AcademicStructureRepository {
  int saves = 0;
  int fetches = 0;
  List<SchoolClassRecord> records = const [];

  @override
  Future<List<SchoolClassRecord>> listClasses({
    required String campusId,
    required String academicYearId,
  }) async {
    fetches++;
    return records;
  }

  @override
  Future<void> createClassWithSections({
    required String schoolId,
    required String campusId,
    required String academicYearId,
    required String className,
    required int sortOrder,
    required List<String> sectionNames,
  }) async {
    if (schoolId != 'school-test' || campusId != 'campus-a' ||
        academicYearId != 'year-test') {
      throw StateError('Incorrect scope');
    }
    saves++;
    records = [
      ...records,
      SchoolClassRecord(
        id: 'class-$saves',
        name: className,
        sortOrder: sortOrder,
        sections: [
          for (var i = 0; i < sectionNames.length; i++)
            SchoolSectionRecord(id: 'section-$i', name: sectionNames[i]),
        ],
      ),
    ];
  }
}

void main() {
  const owner = OwnerAccess(
    userId: 'owner-test',
    displayName: 'Test Owner',
    schoolId: 'school-test',
    schoolName: 'Supa Model School',
    setupComplete: true,
    activeYearId: 'year-test',
    activeYearLabel: '2026-2027',
    campuses: [OwnerCampus(id: 'campus-a', name: 'Main Campus')],
  );

  testWidgets('Class creation validates input and refreshes real scope',
      (tester) async {
    final repo = FakeAcademicRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AcademicStructurePage(
        owner: owner,
        repository: repo,
      )),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('academic-structure-page')), findsOneWidget);
    expect(find.text('No classes created for this campus and academic year yet.'),
        findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('academic-create-class')));
    await tester.tap(find.byKey(const Key('academic-create-class')));
    await tester.pump();
    expect(repo.saves, 0);
    expect(find.text('Enter a class name (1–100 characters).'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('academic-class-name')), 'Grade 1');
    await tester.enterText(
        find.byKey(const Key('academic-section-names')), 'A, B');
    await tester.ensureVisible(find.byKey(const Key('academic-create-class')));
    await tester.tap(find.byKey(const Key('academic-create-class')));
    await tester.pumpAndSettle();

    expect(repo.saves, 1);
    expect(find.text('Grade 1'), findsOneWidget);
    expect(find.byKey(const Key('class-class-1')), findsOneWidget);
  });

  testWidgets('Incomplete Owner setup never enables the class form',
      (tester) async {
    final repo = FakeAcademicRepository();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AcademicStructurePage(
        owner: const OwnerAccess(
          userId: 'owner-test',
          displayName: 'Test Owner',
          schoolId: 'school-test',
          schoolName: 'Supa Model School',
          campuses: [OwnerCampus(id: 'campus-a', name: 'Setup Pending')],
        ),
        repository: repo,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Complete the Owner school setup'), findsOneWidget);
    expect(find.byKey(const Key('academic-create-class')), findsNothing);
    expect(repo.saves, 0);
    expect(repo.fetches, 0);
  });
}
