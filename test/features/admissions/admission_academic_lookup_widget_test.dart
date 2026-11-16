import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/academics/data/academic_structure_repository.dart';
import 'package:supa_model_school/features/admissions/models/admission_draft.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeAdmissionAcademicRepository implements AcademicStructureRepository {
  final requests = <String>[];
  int createCalls = 0;

  @override
  Future<List<SchoolClassRecord>> listClasses({
    required String campusId,
    required String academicYearId,
  }) async {
    requests.add('$campusId/$academicYearId');
    if (academicYearId != 'year-active') {
      throw StateError('Unexpected academic year');
    }
    if (campusId == 'campus-a') {
      return const [
        SchoolClassRecord(
          id: 'grade-one', name: 'Grade 1', sortOrder: 1,
          sections: [
            SchoolSectionRecord(id: 'section-a', name: 'A'),
            SchoolSectionRecord(id: 'section-b', name: 'B'),
          ],
        ),
      ];
    }
    if (campusId == 'campus-b') {
      return const [
        SchoolClassRecord(
          id: 'grade-two', name: 'Grade 2', sortOrder: 2,
          sections: [SchoolSectionRecord(id: 'section-c', name: 'C')],
        ),
      ];
    }
    throw StateError('Unauthorized campus');
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
    createCalls++;
    throw StateError('Admissions should never create academic masters');
  }
}

void main() {
  const authorizedOwner = OwnerAccess(
    userId: 'fixture-owner',
    displayName: 'Fixture Owner',
    schoolId: 'school-fixture',
    schoolName: 'School Fixture',
    setupComplete: true,
    activeYearId: 'year-active',
    activeYearLabel: '2026–2027',
    campuses: [
      OwnerCampus(id: 'campus-a', name: 'Main Campus'),
      OwnerCampus(id: 'campus-b', name: 'Junior Campus'),
    ],
  );

  testWidgets('Preview cannot invent academic choices or save admissions',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(initialStep: AdmissionStep.academic),
    ));
    expect(find.textContaining('No authorized academic options'), findsOneWidget);
    expect(find.textContaining('sample-campus'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('wizard-next')));
    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pump();
    expect(find.byKey(const Key('admission-validation-error')), findsOneWidget);
    expect(find.textContaining('Complete Owner school setup'), findsWidgets);
  });

  testWidgets('Only authorized campus and active-year DB01 options appear',
      (tester) async {
    final repo = FakeAdmissionAcademicRepository();
    await tester.pumpWidget(MaterialApp(
      home: AdmissionWizardPage(
        owner: authorizedOwner,
        academicRepository: repo,
        initialStep: AdmissionStep.academic,
      ),
    ));

    expect(find.byKey(const Key('admission-campus-choice')), findsOneWidget);
    expect(find.byKey(const Key('admission-year-choice')), findsOneWidget);
    expect(find.text('2026–2027'), findsOneWidget);
    expect(repo.requests, isEmpty);

    await tester.ensureVisible(find.byKey(const Key('admission-campus-choice')));
    await tester.tap(find.byKey(const Key('admission-campus-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Campus').last);
    await tester.pumpAndSettle();
    expect(repo.requests, ['campus-a/year-active']);

    expect(find.text('Grade 1'), findsOneWidget);
    await tester.ensureVisible(find.text('Class *'));
    await tester.tap(find.text('Class *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 1').last);
    await tester.pumpAndSettle();

    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(repo.createCalls, 0);
    expect(find.text('Submit unavailable'), findsNothing);
  });

  testWidgets('Changing campus reloads classes and clears old selection',
      (tester) async {
    final repo = FakeAdmissionAcademicRepository();
    await tester.pumpWidget(MaterialApp(
      home: AdmissionWizardPage(
        owner: authorizedOwner,
        academicRepository: repo,
        initialStep: AdmissionStep.academic,
      ),
    ));
    await tester.tap(find.byKey(const Key('admission-campus-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Main Campus').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admission-campus-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Junior Campus').last);
    await tester.pumpAndSettle();

    expect(repo.requests, ['campus-a/year-active', 'campus-b/year-active']);
    expect(find.text('Grade 1'), findsNothing);
    expect(find.text('Grade 2'), findsOneWidget);
    expect(repo.createCalls, 0);
  });
}
