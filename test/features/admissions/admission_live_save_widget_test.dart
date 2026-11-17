import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_draft_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeDrafts implements AdmissionDraftRepository {
  int calls = 0;
  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) async {
    calls++;
    return const SavedAdmissionDraft(id: 'fake-draft-id', revision: 1);
  }
}

const owner = OwnerAccess(
  userId: 'fixture-owner', displayName: 'Test Owner',
  schoolId: 'fixture-school', schoolName: 'Supa Model School',
  setupComplete: true, activeYearId: 'fixture-year',
  activeYearLabel: '2026-2027',
  campuses: [OwnerCampus(id: 'fixture-campus', name: 'Main Campus')],
);

void main() {
  testWidgets('signed-in Owner can request Save Draft but incomplete form is blocked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1550, 950));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final repo = FakeDrafts();
    await tester.pumpWidget(MaterialApp(
      home: AdmissionWizardPage(owner: owner, admissionRepository: repo),
    ));
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('admission-save-draft-disabled')));
    expect(button.onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('admission-save-draft-disabled')));
    await tester.pump();
    expect(repo.calls, 0);
  });

  testWidgets('unauthenticated preview never enables Supabase draft saving',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1550, 950));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: AdmissionWizardPage(),
    ));
    await tester.pumpAndSettle();
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('admission-save-draft-disabled')));
    expect(button.onPressed, isNull);
  });
}
