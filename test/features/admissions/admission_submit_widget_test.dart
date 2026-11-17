import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_approval_repository.dart';
import 'package:supa_model_school/features/admissions/data/admission_draft_repository.dart';
import 'package:supa_model_school/features/admissions/data/admission_document_service.dart';
import 'package:supa_model_school/features/admissions/models/admission_draft.dart';
import 'package:supa_model_school/features/admissions/presentation/admission_wizard_page.dart';
import 'package:supa_model_school/features/academics/data/academic_structure_repository.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';

class FakeAcademics implements AcademicStructureRepository {
  const FakeAcademics();
  @override
  Future<List<SchoolClassRecord>> listClasses({
    required String campusId, required String academicYearId,
  }) async => [
    const SchoolClassRecord(id:'class-1',name:'Grade 1',sortOrder:1,
      sections:[SchoolSectionRecord(id:'section-1',name:'A')]),
  ];
  @override
  Future<void> createClassWithSections({
    required String schoolId,required String campusId,
    required String academicYearId,required String className,
    required int sortOrder,required List<String> sectionNames,
  }) async => throw UnimplementedError();
}

class FakeDrafts implements AdmissionDraftRepository {
  @override
  Future<SavedAdmissionDraft> saveDraft(AdmissionDraftSaveRequest request) =>
    throw UnimplementedError();
  @override
  Future<List<AdmissionDraftRecord>> listDrafts({
    required String schoolId,required String campusId,
  }) async => const [];
}

class FakeDocuments implements AdmissionDocumentService {
  const FakeDocuments({this.status='verified'});
  final String status;
  @override
  Future<List<AdmissionDocumentRecord>> listDocuments(String id) async => [
    AdmissionDocumentRecord(id:'doc-1',kind:'birth_certificate',
      status:status,revision:2,required:true,applicable:true,version:1),
  ];
  @override
  Future<bool> pickAndUpload({
    required String schoolId,required String campusId,
    required String applicationId,required AdmissionDocumentRecord document,
  }) => throw UnimplementedError();
}

class FakeApproval implements AdmissionApprovalRepository {
  int count=0;
  AdmissionSubmitRequest? last;
  @override
  Future<AdmissionSubmitResult> submit(AdmissionSubmitRequest request) async {
    count++;
    last=request;
    return const AdmissionSubmitResult(
      applicationId:'application-1',documentState:'complete',
      principalRequired:true);
  }
  @override
  Future<List<PrincipalApprovalItem>> listPending({
    required String schoolId,required String campusId,
  }) async => const [];
  @override
  Future<PrincipalDecisionResult> review({
    required String applicationId,required int expectedRevision,
    required String operationId,required String decision,String? reason,
  }) => throw UnimplementedError();
  @override
  Future<List<PrincipalDocumentRecord>> listDocuments(String applicationId) async =>
    const [];
  @override
  Future<String> signedDocumentUrl(PrincipalDocumentRecord record) =>
    throw UnimplementedError();
  @override
  Future<void> reviewDocument({
    required String documentId,required int expectedRevision,
    required String operationId,required String decision,String? reason,
  }) => throw UnimplementedError();
}

const owner=OwnerAccess(
 userId:'owner-1',displayName:'Owner',schoolId:'school-1',
 schoolName:'Supa Model School',setupComplete:true,
 activeYearId:'year-1',activeYearLabel:'2026-2027',
 campuses:[OwnerCampus(id:'campus-1',name:'Main Campus')],
);

void main(){
 testWidgets('Owner forwards verified draft, not enrolled by client', (tester) async{
   await tester.binding.setSurfaceSize(const Size(1550,950));
   addTearDown(()=>tester.binding.setSurfaceSize(null));
   final approval=FakeApproval();
   await tester.pumpWidget(MaterialApp(home:AdmissionWizardPage(
     owner:owner,
     initialStep:AdmissionStep.review,
     selectedCampusId:'campus-1',
     academicRepository:const FakeAcademics(),
     admissionRepository:FakeDrafts(),
     documentService:FakeDocuments(),
     approvalRepository:approval,
     initialRecord:AdmissionDraftRecord(
       id:'application-1',revision:4,name:'TEST Review Applicant',
       status:'draft',campusId:'campus-1',academicYearId:'year-1',
       classId:'class-1',sectionId:'section-1',
       dateOfBirth:DateTime(2018,1,1),
       guardians:const [
         {'full_name':'TEST Guardian','relationship':'father',
         'phone':'03001234567','is_primary':true,'is_legal_guardian':true},
       ],
       documents:const [],
     ),
   )));
   await tester.pumpAndSettle();
   final submit=find.byKey(const Key('wizard-submit-disabled'));
   expect(submit,findsOneWidget);
   expect(tester.widget<FilledButton>(submit).onPressed,isNotNull);
   await tester.tap(submit);
   await tester.pumpAndSettle();
   expect(approval.count,0);
   await tester.tap(find.text('Forward for Approval'));
   await tester.pumpAndSettle();
   expect(approval.count,1);
   expect(approval.last?.applicationId,'application-1');
   expect(approval.last?.expectedRevision,4);
   expect(approval.last?.conditionalDue,isNull);
   expect(tester.widget<FilledButton>(submit).onPressed,isNull);
 });
 testWidgets('uploaded certificate submits without a deadline before verification',
    (tester) async {
   await tester.binding.setSurfaceSize(const Size(1550,950));
   addTearDown(()=>tester.binding.setSurfaceSize(null));
   final approval=FakeApproval();
   await tester.pumpWidget(MaterialApp(home:AdmissionWizardPage(
     owner:owner, initialStep:AdmissionStep.review,
     selectedCampusId:'campus-1',
     academicRepository:const FakeAcademics(),
     admissionRepository:FakeDrafts(),
     documentService:const FakeDocuments(status:'uploaded'),
     approvalRepository:approval,
     initialRecord:AdmissionDraftRecord(
       id:'application-1',revision:4,name:'TEST Uploaded Applicant',
       status:'draft',campusId:'campus-1',academicYearId:'year-1',
       classId:'class-1',sectionId:'section-1',
       dateOfBirth:DateTime(2018,1,1),
       guardians:const [
         {'full_name':'TEST Guardian','relationship':'father',
          'phone':'03001234567','is_primary':true,'is_legal_guardian':true},
       ],
       documents:const [],
     ),
   )));
   await tester.pumpAndSettle();
   final submit=find.byKey(const Key('wizard-submit-disabled'));
   expect(tester.widget<FilledButton>(submit).onPressed,isNotNull);
   await tester.tap(submit);
   await tester.pumpAndSettle();
   await tester.tap(find.text('Forward for Approval'));
   await tester.pumpAndSettle();
   expect(approval.count,1);
   expect(approval.last?.conditionalDue,isNull);
   expect(approval.last?.conditionalReason,isNull);
 });
 test('conditional deadline only for missing or rejected documents',(){
   final draft=AdmissionDraft();
   expect(draft.validateStep(AdmissionStep.documents,
      documentsOutstanding:false),isNull);
   expect(draft.validateStep(AdmissionStep.documents,
      documentsOutstanding:true),contains('deadline'));
 });

}
