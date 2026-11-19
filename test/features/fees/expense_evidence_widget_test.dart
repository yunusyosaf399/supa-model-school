import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/expense_evidence_repository.dart';
import 'package:supa_model_school/features/fees/data/expense_repository.dart';
import 'package:supa_model_school/features/fees/presentation/expense_evidence_page.dart';
import 'package:supa_model_school/features/fees/presentation/expense_management_page.dart';

const payment=ExpensePayment(id:'payment-1',amountMinor:12000,
  paidOn:'2026-11-18',accountId:'bank-1');
const request=ExpenseRequest(id:'request-1',categoryId:'category-1',
  category:'Lab Equipment',kind:'capital_asset',amountMinor:12000,
  paidMinor:12000,expenseDate:'2026-11-18',purpose:'Lab oscilloscope',
  status:'recorded',requesterId:'user-1',payments:[payment]);
const evidenceEntry=ExpenseEvidence(id:'evidence-1',kind:'receipt',
  path:'school/campus/request-1/payment-1/object.pdf',
  fileName:'payment.pdf',status:'pending',bytes:1024,
  uploadedAt:'2026-11-18',paymentId:'payment-1');

class EvidenceFake implements ExpenseEvidenceRepository {
  EvidenceFake({this.owner=false});
  final bool owner;
  int reviews=0,uploads=0;
  String? lastPayment,lastKind;
  String status='pending';
  @override
  Future<ExpenseEvidenceWorkspace> list({required String schoolId,
    required String campusId,required String requestId})async{
    expect(schoolId,'school-1');expect(campusId,'campus-1');
    expect(requestId,'request-1');
    return ExpenseEvidenceWorkspace(isOwner:owner,requestStatus:'recorded',
      canUploadInvoice:true,canUploadReceipt:owner,
      attachments:[ExpenseEvidence(id:evidenceEntry.id,kind:evidenceEntry.kind,
        path:evidenceEntry.path,fileName:evidenceEntry.fileName,status:status,
        bytes:evidenceEntry.bytes,uploadedAt:evidenceEntry.uploadedAt,
        paymentId:evidenceEntry.paymentId)]);
  }
  @override
  Future<bool> pickAndUpload({required String schoolId,
    required String campusId,required String requestId,
    required String kind,String? paymentId})async{
    uploads++;lastKind=kind;lastPayment=paymentId;return true;
  }
  @override
  Future<void> review({required String schoolId,required String campusId,
    required String attachmentId,required String decision,String? reason})async{
    expect(attachmentId,'evidence-1');reviews++;status=decision;
  }
  @override
  Future<String> signedPreview(ExpenseEvidence attachment)async=>
    'https://example.com/short-lived-preview';
}
const testWorkspace=ExpenseWorkspace(schoolId:'school-1',campusId:'campus-1',
  currency:'PKR',timezone:'Asia/Karachi',isOwner:true,
  canCreate:true,canRead:true,canPay:true,
  categories:[],accounts:[],requests:[request]);

class RequestFake implements ExpenseRepository {
  @override
  Future<ExpenseWorkspace> workspace({required String schoolId,
    required String campusId})async=>testWorkspace;
  @override
  Future<String> createCategory({required String schoolId,required String code,
    required String name,required String kind,required String operationId})async=>'unused';
  @override
  Future<String> createAccount({required String schoolId,required String campusId,
    required String name,required String kind,String? maskedReference,
    required String operationId})async=>'unused';
  @override
  Future<String> request({required String schoolId,required String campusId,
    required String categoryId,required int amountMinor,
    required String expenseDate,required String purpose,
    required String operationId})async=>'unused';
  @override
  Future<String> review({required String schoolId,required String campusId,
    required String requestId,required String decision,
    String? reason,required String operationId})async=>'unused';
  @override
  Future<ExpensePaidResult> pay({required String schoolId,
    required String campusId,required String requestId,
    required String accountId,required int amountMinor,
    required String paidOn,String? vendor,String? reference,
    required String operationId})async=>const ExpensePaidResult(
      paymentId:'unused',journalId:'unused',amountMinor:0,remainingMinor:0);
}

void main(){
  test('evidence type and signature checks reject masquerading documents',(){
    expect(ExpenseEvidenceValidator.validBytes(
      Uint8List.fromList([0x25,0x50,0x44,0x46,0x2d]),'pdf'),true);
    expect(ExpenseEvidenceValidator.validBytes(
      Uint8List.fromList([0x41,0x42,0x43,0x44,0x45]),'pdf'),false);
    expect(ExpenseEvidenceValidator.validBytes(Uint8List(0),'jpg'),false);
    expect(ExpenseEvidenceValidator.mime('exe'),null);
    expect(ExpenseEvidenceValidator.maxBytes,10485760);
  });
  testWidgets('Owner can optionally attach invoice and posted-payment receipt',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(1000,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final fake=EvidenceFake(owner:true);
    await tester.pumpWidget(MaterialApp(home:ExpenseEvidencePage(
      repository:fake,workspace:testWorkspace,request:request)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Linked posted payment: payment-1'),findsOneWidget);
    expect(find.byKey(const Key('expense-upload-invoice')),findsOneWidget);
    expect(find.byKey(const Key('expense-upload-receipt')),findsOneWidget);
    expect(find.byKey(const Key('expense-evidence-verify-evidence-1')),findsNothing);
    await tester.ensureVisible(find.byKey(const Key('expense-upload-invoice')));
    await tester.tap(find.byKey(const Key('expense-upload-invoice')));
    await tester.pumpAndSettle();
    expect(fake.uploads,1);
    expect(fake.lastKind,'invoice');
    expect(fake.lastPayment,isNull);
    await tester.ensureVisible(find.byKey(const Key('expense-upload-receipt')));
    await tester.tap(find.byKey(const Key('expense-upload-receipt')));
    await tester.pumpAndSettle();
    expect(fake.uploads,2);
    expect(fake.lastKind,'receipt');
    expect(fake.lastPayment,'payment-1');
    expect(fake.reviews,0);
    expect(tester.takeException(),isNull);
  });
  testWidgets('staff may see receipt but cannot verify or upload one',
    (tester)async{
    final fake=EvidenceFake();
    await tester.pumpWidget(MaterialApp(home:ExpenseEvidencePage(
      repository:fake,workspace:testWorkspace,request:request)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-evidence-verify-evidence-1')),findsNothing);
    expect(find.byKey(const Key('expense-upload-receipt')),findsNothing);
    expect(find.byKey(const Key('expense-upload-invoice')),findsOneWidget);
    expect(find.textContaining('Linked posted payment: payment-1'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
  testWidgets('expense request opens attached evidence from finance list',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(1200,1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final fake=EvidenceFake(owner:true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:ExpenseManagementPage(repository:RequestFake(),
        evidenceRepository:fake,schoolId:'school-1',campusId:'campus-1'))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('expense-evidence-request-1')));
    await tester.tap(find.byKey(const Key('expense-evidence-request-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('expense-evidence-page')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
