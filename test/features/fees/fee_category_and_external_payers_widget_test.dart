import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/fee_billing_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_category_generation_page.dart';
import 'package:supa_model_school/features/fees/presentation/fee_other_people_page.dart';

const chargedStudent=FeePaymentStudent(
  id:'s-1',name:'SAMPLE Areeba',registration:'SAMPLE-2026-01',
  classId:'grade-1',className:'Grade 1',sectionId:'A',
  sectionName:'A',charges:[]);
const tuition=FeePaymentCategory(id:'tuition',code:'TUITION',
  name:'Tuition',frequency:'monthly',active:true);
const transport=FeePaymentCategory(id:'transport',code:'TRANSPORT',
  name:'Transport',frequency:'monthly',active:true);
FeePaymentWorkspace exampleWorkspace()=>FeePaymentWorkspace(
  schoolId:'school',campusId:'campus',yearId:'2026-year',
  yearLabel:'2026-27',currency:'PKR',canCollect:true,
  years:const [FeeYearChoice('2026-year','2026-27',true)],
  categories:const [tuition,transport],
  students:const [chargedStudent]);

const otherCharge=OtherPersonCharge(
  id:'charge-1',categoryId:'transport',categoryName:'Transport',
  frequency:'monthly',amountMinor:11000,paidMinor:0,
  outstandingMinor:11000,dueOn:'2026-11-30',
  memo:'External vehicle service');
OtherPeopleLedger exampleExternal({bool collect=true})=>OtherPeopleLedger(
  schoolId:'school',campusId:'campus',yearId:'2026-year',currency:'PKR',
  canCollect:collect,categories:const [transport],
  people:const [
    OtherPersonAccount(id:'person-1',name:'SAMPLE Visitor',
      contact:'000123',charges:[otherCharge],receipts:[]),
  ]);
class FakeBilling implements FeeBillingRepository{
  int generated=0,charged=0,collected=0,created=0;
  int? lastOverride;
  String? lastScope,lastTarget,lastCategory;
  List<QuickPayAllocation>? lastAlloc;
  @override
  Future<CategoryBillResult> generateCategory({
    required String schoolId,required String campusId,required String yearId,
    required String month,required String categoryId,required String scope,
    String? targetId,int? overrideMinor,
    required bool includeOptional,required String operationId})async {
    generated++;lastScope=scope;lastTarget=targetId;
    lastOverride=overrideMinor;lastCategory=categoryId;
    expect(month,'2026-11-01');
    return const CategoryBillResult(
      added:1,skipped:0,eligible:1,category:'Transport');
  }
  @override
  Future<OtherPeopleLedger> otherPeople({required String schoolId,
    required String campusId,required String yearId})async=>exampleExternal();
  @override
  Future<String> createPerson({required String schoolId,
    required String campusId,required String name,String? contact,
    required String operationId}) async {
    created++;return 'person-2';
  }
  @override
  Future<String> chargePerson({required String schoolId,
    required String campusId,required String yearId,
    required String personId,required String categoryId,
    required int amountMinor,required String dueOn,
    required String memo,required String operationId})async {
    expect(personId,'person-1');expect(categoryId,'transport');
    expect(amountMinor,25000);charged++;return 'new-charge';
  }
  @override
  Future<QuickPayReceipt> collectPerson({required String schoolId,
    required String campusId,required String yearId,required String personId,
    required int amountMinor,required String method,String? bankRef,
    required List<QuickPayAllocation> allocations,
    required String operationId})async {
    expect(personId,'person-1');expect(amountMinor,5000);
    expect(method,'cash');lastAlloc=allocations;collected++;
    return const QuickPayReceipt('receipt-1','SMS-000001245',5000);
  }
}

void main(){
  testWidgets('Single student gets manually configured transport charge',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(480,940));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeBilling();
    await tester.pumpWidget(MaterialApp(home:FeeCategoryGenerationPage(
      repository:repo,workspace:exampleWorkspace(),
      initialStudentId:'s-1',initialMonth:'2026-11-01')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-generate-category-page')),findsOneWidget);
    expect(find.textContaining('2026-27'),findsOneWidget);
    await tester.tap(find.byKey(const Key('fee-generate-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Transport • monthly').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('fee-generate-custom-amount')));
    await tester.tap(find.byKey(const Key('fee-generate-custom-amount')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('fee-generate-custom-value')),'300.00');
    await tester.scrollUntilVisible(
      find.byKey(const Key('fee-generate-process')),170);
    await tester.tap(find.byKey(const Key('fee-generate-process')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-generate-confirm')));
    await tester.pumpAndSettle();
    expect(repo.generated,1);
    expect(repo.lastTarget,'s-1');
    expect(repo.lastScope,'student');
    expect(repo.lastOverride,30000);
    expect(repo.lastCategory,'transport');
    expect(find.textContaining('Generated 1 Transport'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('External payer shows owed charges and can generate an invoice',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(980,850));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeBilling();
    await tester.pumpWidget(MaterialApp(home:FeeOtherPeoplePage(
      repository:repo,schoolId:'school',campusId:'campus',
      yearId:'2026-year')));
    await tester.pumpAndSettle();
    expect(find.text('SAMPLE Visitor'),findsOneWidget);
    expect(find.textContaining('PKR 110.00'),findsWidgets);
    await tester.tap(find.byKey(const Key('fee-other-add-charge-person-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(
      const Key('fee-other-charge-amount')),'250.00');
    await tester.enterText(find.byKey(
      const Key('fee-other-charge-date')),'2026-11-25');
    await tester.tap(find.byKey(const Key('fee-other-post-charge')));
    await tester.pumpAndSettle();
    expect(repo.charged,1);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Non-student Quick Pay reviews allocations and issues receipt',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(480,940));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeBilling();
    final w=exampleExternal();
    await tester.pumpWidget(MaterialApp(home:OtherPersonQuickPayPage(
      repository:repo,ledger:w,person:w.people.first)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('fee-other-pay-amount')),'50.00');
    await tester.tap(find.byKey(const Key('fee-other-pay-review')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-other-alloc-charge-1')),findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('fee-other-pay-process')),180);
    await tester.tap(find.byKey(const Key('fee-other-pay-process')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-other-confirm-collect')));
    await tester.pumpAndSettle();
    expect(repo.collected,1);
    expect(repo.lastAlloc!.single.amountMinor,5000);
    expect(find.textContaining('SMS-000001245'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Payers can be read only when write grant is absent',
    (tester) async{
    await tester.binding.setSurfaceSize(const Size(900,800));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    // The RPC controls canCollect. Read-only staff may inspect ledger
    // but must not see payment actions.
    final repo=FakeBilling();
    await tester.pumpWidget(MaterialApp(home:FeeOtherPeoplePage(
      repository:repo,schoolId:'school',campusId:'campus',
      yearId:'2026-year')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-other-payers-page')),findsOneWidget);
  });
}
