import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/fee_billing_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/presentation/individual_fee_page.dart';

const _student=FeePaymentStudent(
  id:'student-a',name:'SAMPLE Student A',registration:'TEST-A-001',
  classId:'grade4',className:'Grade 4',sectionId:'a',sectionName:'A',
  charges:[]);
const _otherStudent=FeePaymentStudent(
  id:'student-b',name:'SAMPLE Student B',registration:'TEST-B-001',
  classId:'grade4',className:'Grade 4',sectionId:'a',sectionName:'A',
  charges:[]);
const _uniform=FeePaymentCategory(
  id:'uniform',code:'UNIFORM',name:'Uniform',
  frequency:'one_time',active:true);
const _tuition=FeePaymentCategory(
  id:'tuition',code:'TUITION',name:'Tuition',
  frequency:'monthly',active:true);
const _workspace=FeePaymentWorkspace(
  schoolId:'test-school',campusId:'test-campus',yearId:'test-year',
  yearLabel:'2026-2027',currency:'PKR',canCollect:true,
  years:[FeeYearChoice('test-year','2026-2027',true)],
  categories:[_tuition,_uniform],
  students:[_student,_otherStudent]);

class IndividualChargeCall {
  IndividualChargeCall(this.student,this.category,this.amount,this.priceMode,
    this.description,this.operation);
  final String student,category,priceMode,description,operation;
  final int? amount;
}
class FakeIndividualBilling implements FeeBillingRepository {
  final calls=<IndividualChargeCall>[];
  bool failFirst=false;
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);

  @override
  Future<IndividualFeeResult> addIndividualCharge({
    required String schoolId,required String campusId,required String yearId,
    required String studentId,required String categoryId,
    required String chargeOn,required String dueOn,
    required String priceMode,int? amountMinor,
    required String description,required String operationId,
  }) async {
    expect(schoolId,'test-school');
    expect(campusId,'test-campus');
    expect(yearId,'test-year');
    calls.add(IndividualChargeCall(studentId,categoryId,amountMinor,
      priceMode,description,operationId));
    if(failFirst){failFirst=false;throw Exception('response unavailable');}
    return IndividualFeeResult(chargeId:'charge-'+calls.length.toString(),
      grossMinor:amountMinor??180000,discountMinor:0,
      netMinor:amountMinor??180000,category:'Uniform');
  }
}

Future<void> fillCustom(WidgetTester tester,String amount,String description) async {
  await tester.enterText(find.byKey(const Key('individual-fee-amount')),amount);
  await tester.enterText(find.byKey(const Key('individual-fee-description')),
    description);
  final save=find.byKey(const Key('individual-fee-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main(){
  test('individual result requires a confirmed manual charge',(){
    expect(()=>IndividualFeeResult.fromJson({'saved':false}),
      throwsStateError);
    final x=IndividualFeeResult.fromJson({
      'saved':true,'source':'manual','charge_id':'charge-1',
      'category':'Uniform','gross_minor':245000,
      'discount_minor':0,'net_minor':245000});
    expect(x.chargeId,'charge-1');
    expect(x.netMinor,245000);
  });

  testWidgets('custom Uniform charges only the selected student',
      (tester)async{
    await tester.binding.setSurfaceSize(const Size(600,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeIndividualBilling();
    await tester.pumpWidget(MaterialApp(home:IndividualFeePage(
      workspace:_workspace,repository:repo,initialStudentId:'student-a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('individual-fee-page')),findsOneWidget);
    await fillCustom(tester,'2450.00','Uniform size L, extra trousers');
    expect(find.byKey(const Key('individual-fee-confirm')),findsOneWidget);
    await tester.tap(find.byKey(const Key('individual-fee-confirm')));
    await tester.pumpAndSettle();
    expect(repo.calls.length,1);
    expect(repo.calls.single.student,'student-a');
    expect(repo.calls.single.category,'uniform');
    expect(repo.calls.single.priceMode,'custom');
    expect(repo.calls.single.amount,245000);
    expect(find.byKey(const Key('individual-fee-saved')),findsOneWidget);
  });

  testWidgets('retry uses identical operation ID after response failure',
      (tester)async{
    await tester.binding.setSurfaceSize(const Size(600,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeIndividualBilling()..failFirst=true;
    await tester.pumpWidget(MaterialApp(home:IndividualFeePage(
      workspace:_workspace,repository:repo,initialStudentId:'student-b')));
    await tester.pumpAndSettle();
    await fillCustom(tester,'650.00','Second independent uniform purchase');
    await tester.tap(find.byKey(const Key('individual-fee-confirm')));
    await tester.pumpAndSettle();
    expect(repo.calls.length,1);
    expect(find.textContaining('Fee not confirmed'),findsOneWidget);
    final button=find.byKey(const Key('individual-fee-save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(repo.calls.length,2);
    expect(repo.calls.first.operation,repo.calls.last.operation);
    expect(repo.calls.last.amount,65000);
    expect(find.byKey(const Key('individual-fee-saved')),findsOneWidget);
  });

  testWidgets('invalid individual amount cannot be submitted', (tester)async{
    await tester.binding.setSurfaceSize(const Size(600,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeIndividualBilling();
    await tester.pumpWidget(MaterialApp(home:IndividualFeePage(
      workspace:_workspace,repository:repo,initialStudentId:'student-a')));
    await tester.pumpAndSettle();
    await fillCustom(tester,'0','Uniform for Grade 4 student');
    expect(find.textContaining('valid amount'),findsOneWidget);
    expect(repo.calls,isEmpty);
  });
}
