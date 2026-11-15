import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/main.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';

void main() {
  testWidgets('wizard displays six stages and never advertises cloud saving',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(),
    ));

    expect(find.text('New Student Admission'), findsOneWidget);
    expect(find.byKey(const Key('step-chip-0')), findsOneWidget);
    expect(find.byKey(const Key('step-chip-5')), findsOneWidget);
    expect(find.textContaining('No information is saved'), findsOneWidget);
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
    await tester.pumpWidget(const SupaModelSchoolApp());
    await tester.tap(find.text('Students').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-admission-wizard')), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-admission-wizard')));
    await tester.pumpAndSettle();

    expect(find.text('New Student Admission'), findsOneWidget);
    expect(find.text('Preview • Not saved'), findsOneWidget);
  });
}
