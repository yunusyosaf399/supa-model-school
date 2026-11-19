import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/expense_repository.dart';
import 'package:supa_model_school/features/fees/presentation/expense_management_page.dart';
import 'package:supa_model_school/features/fees/presentation/expense_pay_page.dart';

const category=ExpenseCategory(id:'category-1',code:'REPAIRS',name:'Repairs',
  kind:'operating',active:true);
const account=ExpenseAccount(id:'account-1',name:'Main Cash Box',
  method:'cash',status:'active');
const approvedExpense=ExpenseRequest(
  id:'expense-1',categoryId:'category-1',category:'Repairs',
  kind:'operating',amountMinor:30000,paidMinor:10000,
  expenseDate:'2026-11-18',purpose:'Test classroom maintenance',
  status:'approved',requesterId:'staff-1',payments:[]);
const recordedExpense=ExpenseRequest(
  id:'expense-1',categoryId:'category-1',category:'Repairs',
  kind:'operating',amountMinor:30000,paidMinor:0,
  expenseDate:'2026-11-18',purpose:'Test classroom maintenance',
  status:'recorded',requesterId:'staff-1',payments:[]);
const pendingExpense=ExpenseRequest(
  id:'expense-1',categoryId:'category-1',category:'Repairs',
  kind:'operating',amountMinor:30000,paidMinor:0,
  expenseDate:'2026-11-18',purpose:'Test classroom maintenance',
  status:'pending',requesterId:'staff-1',payments:[]);

class MockExpenses implements ExpenseRepository {
  MockExpenses({this.owner=false,this.create=true,this.read=true,
    this.payAllowed=false,this.hasRequest=false,this.hasAccount=true});
  final bool owner,create,read,payAllowed,hasRequest,hasAccount;
  int submitted=0,approved=0,paid=0,createdCategories=0,createdAccounts=0;
  String? lastReview,lastOperation,lastCategory,lastAccount;
  int? lastAmount;
  ExpenseRequest? current;
  @override
  Future<ExpenseWorkspace> workspace({
    required String schoolId,required String campusId})async {
    expect(schoolId,'school-1');expect(campusId,'campus-1');
    return ExpenseWorkspace(
      schoolId:schoolId,campusId:campusId,currency:'PKR',
      timezone:'Asia/Karachi',isOwner:owner,canCreate:create,
      canRead:read,canPay:owner||payAllowed,
      categories:const [category],
      accounts:hasAccount?const [account]:const [],
      requests:current==null?(hasRequest?const [pendingExpense]:const []):
        [current!],
    );
  }
  @override
  Future<String> createCategory({required String schoolId,
    required String code,required String name,required String kind,
    required String operationId})async {
    createdCategories++;expect(code,'ELECTRICITY');
    return 'new-category';
  }
  @override
  Future<String> createAccount({required String schoolId,
    required String campusId,required String name,required String kind,
    String? maskedReference,required String operationId})async {
    createdAccounts++;return 'new-account';
  }
  @override
  Future<String> request({required String schoolId,required String campusId,
    required String categoryId,required int amountMinor,
    required String expenseDate,required String purpose,
    required String operationId})async {
    submitted++;lastOperation=operationId;lastCategory=categoryId;
    lastAmount=amountMinor;
    current=recordedExpense;return 'expense-1';
  }
  @override
  Future<String> review({required String schoolId,required String campusId,
    required String requestId,required String decision,String? reason,
    required String operationId})async {
    approved++;lastReview=decision;lastOperation=operationId;
    current=decision=='approved'?approvedExpense:pendingExpense;
    return decision;
  }
  @override
  Future<ExpensePaidResult> pay({
    required String schoolId,required String campusId,
    required String requestId,required String accountId,
    required int amountMinor,required String paidOn,
    String? vendor,String? reference,required String operationId})async {
    paid++;lastAmount=amountMinor;lastAccount=accountId;
    lastOperation=operationId;
    return ExpensePaidResult(paymentId:'payment-1',journalId:'journal-1',
      amountMinor:amountMinor,remainingMinor:20000-amountMinor);
  }
}
Future<void> showExpense(tester,MockExpenses fake)async{
  await tester.pumpWidget(MaterialApp(home:Scaffold(
    body:ExpenseManagementPage(repository:fake,
      schoolId:'school-1',campusId:'campus-1'))));
  await tester.pumpAndSettle();
}

void main(){
  test('approved expense computes remaining and does not assume payment',(){
    expect(approvedExpense.remainingMinor,20000);
    expect(approvedExpense.status,'approved');
    expect(pendingExpense.paidMinor,0);
    expect(pendingExpense.remainingMinor,30000);
  });

  testWidgets('staff records expense immediately without approval or payment',
      (tester)async {
    await tester.binding.setSurfaceSize(const Size(1150,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final fake=MockExpenses(create:true,read:true);
    await showExpense(tester,fake);
    expect(find.byKey(const Key('expense-request-form')),findsOneWidget);
    expect(find.byKey(const Key('expense-owner-setup')),findsNothing);
    await tester.tap(find.byKey(const Key('expense-request-form')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('expense-request-amount')),'260.50');
    await tester.enterText(
      find.byKey(const Key('expense-request-purpose')),
      'Replacement classroom electricity plug');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('expense-submit-request')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-submit-request')));
    await tester.pumpAndSettle();
    expect(fake.submitted,1);
    expect(fake.lastAmount,26050);
    expect(fake.lastCategory,'category-1');
    expect(fake.approved,0);
    expect(fake.paid,0);
    expect(fake.current?.status,'recorded');
    expect(find.textContaining('RECORDED'),findsWidgets);
    expect(find.byKey(const Key('expense-approve-expense-1')),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Owner sees recorded expenses with no approval queue',
    (tester)async {
    await tester.binding.setSurfaceSize(const Size(1100,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final fake=MockExpenses(owner:true,hasRequest:true);
    fake.current=recordedExpense;
    await showExpense(tester,fake);
    expect(find.byKey(const Key('expense-owner-setup')),findsOneWidget);
    expect(find.byKey(const Key('expense-approve-expense-1')),findsNothing);
    expect(find.byKey(const Key('expense-reject-expense-1')),findsNothing);
    expect(find.textContaining('RECORDED'),findsWidgets);
    expect(fake.approved,0);
    expect(tester.takeException(),isNull);
  });

  testWidgets('authorized partial cash payment creates journal result',
    (tester)async {
    await tester.binding.setSurfaceSize(const Size(1100,940));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final fake=MockExpenses(owner:true);
    final w=await fake.workspace(schoolId:'school-1',campusId:'campus-1');
    await tester.pumpWidget(MaterialApp(home:ExpensePayPage(
      repository:fake,workspace:w,request:approvedExpense)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(
      const Key('expense-payment-amount')),'150.00');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('expense-payment-process')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-payment-process')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expense-payment-confirm')));
    await tester.pumpAndSettle();
    expect(fake.paid,1);
    expect(fake.lastAmount,15000);
    expect(fake.lastAccount,'account-1');
    expect(find.textContaining('journal-1'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('staff with read-only grant sees no edit or approval options',
    (tester)async {
    await tester.binding.setSurfaceSize(const Size(1100,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final fake=MockExpenses(create:false,read:true,hasRequest:true);
    await showExpense(tester,fake);
    expect(find.byKey(const Key('expense-management-page')),findsOneWidget);
    expect(find.byKey(const Key('expense-request-form')),findsNothing);
    expect(find.byKey(const Key('expense-owner-setup')),findsNothing);
    expect(find.byKey(const Key('expense-approve-expense-1')),findsNothing);
    expect(find.byKey(const Key('expense-pay-expense-1')),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
