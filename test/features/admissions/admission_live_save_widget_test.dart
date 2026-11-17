import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_draft_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeDrafts implements AdmissionDraftRepository {
  int calls = 0;
  AdmissionDraftSaveRequest? lastRequest;
  @override
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId, required String campusId,
  }) async => const [];
  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) async {
    calls++;
    lastRequest = request;
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

  testWidgets('resumed draft saves demographics and transport without changing application ID',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1550, 950));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final repo = FakeDrafts();
    await tester.pumpWidget(MaterialApp(
      home: AdmissionWizardPage(
        owner: owner,
        admissionRepository: repo,
        initialRecord: const AdmissionDraftRecord(
          id: 'application-1', revision: 4,
          name: 'TEST Returning Applicant',
          campusId: 'fixture-campus', academicYearId: 'fixture-year',
          status: 'draft', guardians: [], documents: [],
          extraDetails: {
            'city': 'Peshawar',
            'nationality': 'Pakistani',
            'uses_transport': true,
            'requests_discount': false,
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admission-save-draft-disabled')));
    await tester.pumpAndSettle();
    expect(repo.calls, 1);
    expect(repo.lastRequest?.applicationId, 'application-1');
    expect(repo.lastRequest?.expectedRevision, 4);
    expect(repo.lastRequest?.extraDetails['city'], 'Peshawar');
    expect(repo.lastRequest?.extraDetails['nationality'], 'Pakistani');
    expect(repo.lastRequest?.extraDetails['uses_transport'], true);
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
