import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';
import 'package:supa_model_school/features/admissions/models/admission_draft.dart';

void main() {
  testWidgets('wizard displays six stages and never advertises cloud saving',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(),
    ));

    expect(find.text('New Admission'), findsOneWidget);
    expect(find.byKey(const Key('step-chip-0')), findsOneWidget);
    expect(find.byKey(const Key('step-chip-5')), findsOneWidget);
    expect(find.byKey(const Key('admission-save-draft-disabled')), findsOneWidget);
    expect(find.byKey(const Key('wizard-next')), findsOneWidget);
  });

  testWidgets('empty student fields show a blocking validation message',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(),
    ));

    await tester.tap(find.byKey(const Key('wizard-next')));
    await tester.pump();
    expect(find.byKey(const Key('admission-validation-error')),
        findsOneWidget);
    expect(find.textContaining('full name'), findsOneWidget);
  });

  testWidgets('students module opens admission wizard preview',
      (tester) async {
    await tester.pumpWidget(const SupaModelSchoolApp(startInPreview: true));
    await tester.tap(find.text('Students').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-admission-wizard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-admission-wizard')));
    await tester.pumpAndSettle();

    expect(find.text('New Student Admission'), findsOneWidget);
    expect(find.byKey(const Key('admission-save-draft-disabled')), findsOneWidget);
  });
  testWidgets('Windows screenshot layout provides sidebar and document checklist',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1648, 928));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(),
    ));
    expect(find.byKey(const Key('admission-desktop-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('step-tab-0')), findsOneWidget);
    expect(find.text('Student Details'), findsOneWidget);
    expect(find.text('Contact / Identity Information'), findsOneWidget);
    expect(find.text('Admission Checklist'), findsOneWidget);
    expect(find.text('Admission Status'), findsOneWidget);
    expect(find.byKey(const Key('admission-photo-placeholder')),
        findsOneWidget);
    expect(find.byKey(const Key('admission-save-draft-disabled')),
        findsOneWidget);
  });

  testWidgets('Android screenshot layout has icon steps and fixed bottom actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(),
    ));
    expect(find.byKey(const Key('admission-desktop-sidebar')), findsNothing);
    expect(find.byKey(const Key('step-chip-0')), findsOneWidget);
    expect(find.byKey(const Key('step-chip-5')), findsOneWidget);
    expect(find.byKey(const Key('admission-mobile-greeting')), findsNothing);
    expect(find.byKey(const Key('admission-save-draft-disabled')),
        findsOneWidget);
    expect(find.byKey(const Key('wizard-next')), findsOneWidget);
  });

  testWidgets('debug preview may inspect Review without enabling submission',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: AdmissionWizardPage()));
    await tester.tap(find.byKey(const Key('step-chip-5')));
    await tester.pump();
    expect(find.text('Review Application'), findsWidgets);
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('wizard-submit-disabled')));
    expect(submit.onPressed, isNull);
  });

  testWidgets('All six steps render their distinct form sections',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    const expected = <AdmissionStep, String>{
      AdmissionStep.student: 'Student Details',
      AdmissionStep.guardians: 'Guardian Details',
      AdmissionStep.academic: 'Academic Placement',
      AdmissionStep.documents: 'Required Documents',
      AdmissionStep.fees: 'Fee Setup',
      AdmissionStep.review: 'Review Application',
    };
    for (final entry in expected.entries) {
      await tester.pumpWidget(MaterialApp(
        key: ValueKey('step-${entry.key.index}'),
        home: AdmissionWizardPage(
          key: ValueKey('wizard-${entry.key.index}'),
          initialStep: entry.key,
        ),
      ));
      await tester.pump();
      expect(find.text(entry.value), findsWidgets);
      if (entry.key == AdmissionStep.review) {
        expect(find.byKey(const Key('wizard-submit-disabled')),
            findsOneWidget);
      }
    }
  });

}
