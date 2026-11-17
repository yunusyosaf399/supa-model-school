import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/admissions/data/admission_approval_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/principal_approval_page.dart';
import 'package:supa_model_school/features/admissions/presentation/principal_documents_page.dart';

class FakePrincipalRepository implements AdmissionApprovalRepository {
  FakePrincipalRepository({this.denied=false});
  final bool denied;
  int decisions=0,loads=0;
  String? decision;
  @override
  Future<AdmissionSubmitResult> submit(AdmissionSubmitRequest request) =>
    throw UnimplementedError();
  @override
  Future<List<PrincipalApprovalItem>> listPending({
    required String schoolId,required String campusId,
  }) async {
    loads++;
    if(denied) throw StateError('principal access denied');
    if(schoolId!='school-1' || campusId!='campus-1') {
      throw StateError('wrong scope');
    }
    if(decisions>0) return const [];
    return const [
      PrincipalApprovalItem(id:'app-1',name:'TEST Approval Applicant',
        revision:2,documentState:'conditional',missingDocuments:2,
        conditionalDue:'2026-12-10'),
    ];
  }
  @override
  Future<PrincipalDecisionResult> review({
    required String applicationId, required int expectedRevision,
    required String operationId, required String decision, String? reason,
  }) async {
    if(applicationId!='app-1'||expectedRevision!=2) {
      throw StateError('wrong application/revision');
    }
    this.decision=decision;
    decisions++;
    return PrincipalDecisionResult(applicationId:'app-1',
      status:decision=='approve'?'approved':
        decision=='return'?'returned':'rejected',
      studentId:decision=='approve'?'student-1':null);
  }
  @override
  Future<List<PrincipalDocumentRecord>> listDocuments(String applicationId) async {
    if(denied) throw StateError('unauthorized');
    if(applicationId!='app-1') throw StateError('wrong app');
    return const [
      PrincipalDocumentRecord(id:'doc-1',kind:'birth_certificate',
        status:'uploaded',revision:2,required:true,applicable:true,
        uploadId:'upload-1',version:1,bucket:'sms-admission-documents',
        objectPath:'school/campus/application/document/file.pdf'),
      PrincipalDocumentRecord(id:'doc-2',kind:'transfer_certificate',
        status:'missing',revision:1,required:true,applicable:true),
    ];
  }
  @override
  Future<String> signedDocumentUrl(PrincipalDocumentRecord record) async =>
      throw UnimplementedError('Do not open private links in widget tests');
  @override
  Future<void> reviewDocument({
    required String documentId,required int expectedRevision,
    required String operationId,required String decision,String? reason,
  }) async {}
}

void main() {
  testWidgets('Principal queue shows pending item and conditional deadline',
      (tester) async {
    final repo=FakePrincipalRepository();
    await tester.binding.setSurfaceSize(const Size(1300,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PrincipalApprovalPage(
        schoolId:'school-1',campusId:'campus-1',repository:repo))));
    await tester.pumpAndSettle();
    expect(repo.loads,1);
    expect(find.text('TEST Approval Applicant'),findsOneWidget);
    expect(find.textContaining('Document deadline: 2026-12-10'),findsOneWidget);
    final approve=find.byKey(const Key('principal-approve-app-1'));
    await tester.ensureVisible(approve);
    await tester.tap(approve);
    await tester.pumpAndSettle();
    expect(repo.decisions,0);
    await tester.tap(find.byKey(const Key('principal-confirm-decision')));
    await tester.pumpAndSettle();
    expect(repo.decisions,1);
    expect(repo.decision,'approve');
    expect(find.text('No pending admissions'),findsOneWidget);
  });
  testWidgets('unauthorized Principal queue fails closed', (tester) async {
    final repo=FakePrincipalRepository(denied:true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:PrincipalApprovalPage(
        schoolId:'school-1',campusId:'campus-1',repository:repo))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load the authorized'),findsOneWidget);
    expect(find.text('TEST Approval Applicant'),findsNothing);
  });
  testWidgets('Principal certificate review requires inspection first',
      (tester) async {
    final repo=FakePrincipalRepository();
    await tester.pumpWidget(MaterialApp(
      home:PrincipalDocumentsPage(applicationId:'app-1',repository:repo)));
    await tester.pumpAndSettle();
    expect(find.text('birth_certificate'),findsOneWidget);
    expect(find.text('transfer_certificate'),findsOneWidget);
    final verify=tester.widget<FilledButton>(
      find.byKey(const Key('verify-document-doc-1')));
    expect(verify.onPressed,isNull);
    final noFile=tester.widget<OutlinedButton>(
      find.byKey(const Key('inspect-document-doc-2')));
    expect(noFile.onPressed,isNull);
  });
}
