import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_document_service.dart';
import 'package:supa_model_school/features/admissions/data/admission_draft_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';
import 'package:supa_model_school/features/admissions/models/admission_draft.dart';
import 'package:supa_model_school/features/academics/data/academic_structure_repository.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeDocuments implements AdmissionDocumentService {
  var uploaded = false;
  var photoUploaded = false;
  var calls = 0;
  var photoCalls = 0;

  @override
  Future<List<AdmissionDocumentRecord>> listDocuments(String applicationId) async {
    if (applicationId != 'saved-admission') throw StateError('wrong id');
    return [
      if (photoUploaded)
        const AdmissionDocumentRecord(
          id:'photo-id',kind:'photo',status:'uploaded',revision:2,
          required:false,applicable:true,version:1),
      AdmissionDocumentRecord(
        id: 'document-id', revision: uploaded ? 2 : 1,
        kind: 'birth_certificate', status: uploaded ? 'uploaded' : 'missing',
        required: true, applicable: true, version: uploaded ? 1 : null,
      ),
    ];
  }

  @override
  Future<AdmissionDocumentRecord?> preparePhoto(String applicationId) async {
    expect(applicationId,'saved-admission');
    return const AdmissionDocumentRecord(
      id:'photo-id',kind:'photo',status:'missing',revision:1,
      required:false,applicable:true);
  }

  @override
  Future<bool> pickAndUploadPhoto({
    required String schoolId,required String campusId,
    required String applicationId,required AdmissionDocumentRecord document,
  }) async {
    expect(applicationId,'saved-admission');
    expect(document.kind,'photo');
    expect(document.id,'photo-id');
    photoCalls++;
    photoUploaded=true;
    return true;
  }

  @override
  Future<bool> pickAndUpload({
    required String schoolId,
    required String campusId,
    required String applicationId,
    required AdmissionDocumentRecord document,
  }) async {
    expect(schoolId, 'school-1');
    expect(campusId, 'campus-1');
    expect(applicationId, 'saved-admission');
    expect(document.id, 'document-id');
    calls++;
    uploaded = true;
    return true;
  }
}

class FakeAdmissionDrafts implements AdmissionDraftRepository {
  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) async =>
      const SavedAdmissionDraft(id:'saved-admission', revision:2);
  @override
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId, required String campusId,
  }) async => const [];
}

const owner = OwnerAccess(
  userId:'owner-1', displayName:'Owner',
  schoolId:'school-1', schoolName:'Supa Model School',
  setupComplete:true, activeYearId:'year-1',
  campuses:[OwnerCampus(id:'campus-1',name:'Main Campus')],
);

void main() {
  testWidgets('saved draft certificate upload stays unverified', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final documents = FakeDocuments();
    await tester.pumpWidget(MaterialApp(home: AdmissionWizardPage(
      owner: owner,
      admissionRepository: FakeAdmissionDrafts(),
      academicRepository: const UnconfiguredAcademicStructureRepository(),
      documentService: documents,
      selectedCampusId:'campus-1',
      initialStep:AdmissionStep.documents,
      initialRecord: AdmissionDraftRecord(
        id:'saved-admission',revision:1,status:'draft',
        name:'TEST Admission Student',
        campusId:'campus-1',academicYearId:'year-1',
        guardians:const [],documents:const [],
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('MISSING'), findsWidgets);
    final upload = find.byKey(const Key('admission-upload-birth_certificate'));
    expect(upload, findsOneWidget);
    await tester.ensureVisible(upload);
    await tester.tap(upload);
    await tester.pumpAndSettle();
    expect(documents.calls, 1);
    expect(find.textContaining('UPLOADED'), findsWidgets);
    expect(find.textContaining('Not verified'), findsWidgets);
    expect(find.textContaining('Principal verifies'), findsWidgets);
  });

  testWidgets('student photo uploads from the actual student photo control',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500,1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final documents=FakeDocuments();
    await tester.pumpWidget(MaterialApp(home:AdmissionWizardPage(
      owner:owner,
      admissionRepository:FakeAdmissionDrafts(),
      academicRepository:const UnconfiguredAcademicStructureRepository(),
      documentService:documents,
      selectedCampusId:'campus-1',
      initialStep:AdmissionStep.student,
      initialRecord:AdmissionDraftRecord(
        id:'saved-admission',revision:1,status:'draft',
        name:'TEST Student Photo',campusId:'campus-1',
        academicYearId:'year-1',guardians:const [],documents:const [],
      ),
    )));
    await tester.pumpAndSettle();
    final photo=find.byKey(const Key('admission-photo-upload'));
    expect(photo,findsOneWidget);
    await tester.ensureVisible(photo);
    await tester.tap(photo);
    await tester.pumpAndSettle();
    expect(documents.photoCalls,1);
    expect(documents.photoUploaded,true);
    expect(find.text('Photo Uploaded'),findsOneWidget);
  });
}
