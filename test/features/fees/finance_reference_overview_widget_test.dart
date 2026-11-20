import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/fees/data/fee_cashbook_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_setup_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_monthly_repository.dart';
import 'package:supa_model_school/features/fees/data/school_cashflow_repository.dart';
import 'package:supa_model_school/features/fees/data/finance_overview_model.dart';
import 'package:supa_model_school/features/fees/presentation/fee_finance_page.dart';
import 'package:supa_model_school/features/fees/presentation/finance_overview_widgets.dart';

const owner=OwnerAccess(
  userId:'test-owner',displayName:'School Owner',
  schoolId:'school',schoolName:'Supa Model School',
  activeYearId:'year',activeYearLabel:'2026-2027',
  activeYearStartsOn:'2026-04-01',activeYearEndsOn:'2027-03-31',
  currencyCode:'PKR',
  campuses:[OwnerCampus(id:'campus',name:'Sample Campus A')],
);

const demoStudent=FeePaymentStudent(
  id:'st',name:'Student 1',registration:'SM-001',
  classId:'g1',className:'Grade 1',sectionId:'s1',sectionName:'A',
  charges:[
    FeePaymentCharge(id:'ch',categoryId:'tuition',
      categoryName:'Tuition Fee',frequency:'monthly',
      month:'2026-11-01',dueOn:'2026-11-30',
      netMinor:100000,paidMinor:30000,outstandingMinor:70000),
  ],
);

const workspace=FeePaymentWorkspace(
  schoolId:'school',campusId:'campus',yearId:'year',
  yearLabel:'2026-2027',currency:'PKR',canCollect:true,
  years:[FeeYearChoice('year','2026-2027',true)],
  categories:[
    FeePaymentCategory(id:'tuition',code:'TUITION',
      name:'Tuition Fee',frequency:'monthly',active:true),
    FeePaymentCategory(id:'transport',code:'TRANSPORT',
      name:'Transport Fee',frequency:'monthly',active:true),
  ],
  students:[demoStudent],
);

FeeCashbookReport cashbook(String from,String to)=>
  FeeCashbookReport.fromJson({
    'school_id':'school','campus_id':'campus','year_id':'year',
    'currency':'PKR','timezone':'Etc/UTC',
    'from':from,'to':to,'method':'all','source':'all',
    'summary':{
      'amount_minor':150000,'cash_minor':150000,'bank_minor':0,
      'student_minor':150000,'other_minor':0,'receipt_count':2,
      'allocation_lines':2,
    },
    'daily':[
      {'date':'2026-10-15','amount_minor':50000,'cash_minor':50000,
       'bank_minor':0,'student_minor':50000,'other_minor':0},
      {'date':'2026-11-12','amount_minor':100000,'cash_minor':100000,
       'bank_minor':0,'student_minor':100000,'other_minor':0},
    ],
    'category_totals':[
      {'id':'tuition','name':'Tuition Fee','frequency':'monthly',
        'amount_minor':120000},
      {'id':'transport','name':'Transport Fee','frequency':'monthly',
        'amount_minor':30000},
    ],
    'entries':[],
    'year_options':[],'campus_options':[],
    'category_options':[],'class_options':[],
    'unbalanced_receipts':0,
  });

SchoolCashflowReport cashflow(String from,String to)=>
  SchoolCashflowReport.fromJson({
    'school_id':'school','campus_id':'campus','year_id':'year',
    'from':from,'to':to,'timezone':'Etc/UTC','currency':'PKR',
    'scope_note':'School finance read scope',
    'summary':{
      'inflow_minor':150000,'outflow_minor':80000,
      'net_movement_minor':70000,'student_fee_minor':150000,
      'other_fee_minor':0,'canteen_minor':0,'uniform_minor':0,
      'expense_minor':30000,'salary_minor':50000,'fee_refund_minor':0,
      'cash_in_minor':150000,'bank_in_minor':0,
      'cash_out_minor':80000,'bank_out_minor':0,
      'transaction_lines':3,
    },
    'daily':[],
    'entries':[
      {'date':'2026-11-15','source':'student_fee','kind':'receipt',
        'reference':'SM-001','counterparty':'Student 1',
        'category':'Tuition','method':'cash','signed_minor':150000},
      {'date':'2026-11-12','source':'salary','kind':'salary_payment',
        'reference':'SAL-1','counterparty':'Teacher A',
        'category':'Salary','method':'cash','signed_minor':-50000},
      {'date':'2026-11-10','source':'expense','kind':'expense',
        'reference':'EXP-1','counterparty':'Stationery',
        'category':'Stationery','method':'cash','signed_minor':-30000},
    ],
    'cancelled_retail_minor':0,'cancelled_retail_count':0,
    'direct_stock_cost_minor':0,'pending_expense_requests':0,
    'unbalanced_fee_receipts':0,
    'campus_options':[],'year_options':[],
  });

class FakeWorkspace implements FeePaymentRepository{
  int reads=0;
  bool fail=false;
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
  @override Future<FeePaymentWorkspace> workspace({
    required String schoolId,required String campusId,String? yearId,
  })async{
    reads++;
    if(fail)throw StateError('No network');
    expect(schoolId,'school');expect(campusId,'campus');
    expect(yearId,'year');
    return workspace;
  }
}

class FakeCashbook implements FeeCashbookRepository{
  int calls=0;
  @override Future<FeeCashbookReport> load({
    required String schoolId,required String yearId,
    required String from,required String to,
    required String method,required String source,
    String? campusId,String? categoryId,String? classId,
  })async{
    calls++;
    expect(schoolId,'school');expect(campusId,'campus');
    expect(to.compareTo(from)>=0,isTrue);
    expect(method,'all');expect(source,'all');
    final f=DateTime.parse(from),t=DateTime.parse(to);
    expect(t.difference(f).inDays,lessThanOrEqualTo(92));
    return cashbook(from,to);
  }
}
class FakeMovement implements SchoolCashflowRepository{
  int calls=0;
  @override Future<SchoolCashflowReport> load({
    required String schoolId,required String yearId,
    String? campusId,required String from,required String to,
  })async{
    calls++;
    expect(schoolId,'school');expect(campusId,'campus');
    return cashflow(from,to);
  }
}
class FakeMonthly implements FeeMonthlyRepository{
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
class FakeSetup implements FeeSetupRepository{
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}

FinanceOverviewSnapshot snapshot()=>FinanceOverviewSnapshot.fromReports(
  today:DateTime(2026,11,20),workspace:workspace,
  cashbooks:[cashbook('2026-10-01','2026-11-20')],
  cashflows:[cashflow('2026-10-01','2026-11-20')],
  periodStart:'2026-10-01',periodEnd:'2026-11-20');

void main(){
  test('Six-month windows obey year bounds and RPC limit',(){
    final ranges=financeOverviewWindows(DateTime(2026,11,20),
      academicStart:DateTime(2026,7,1));
    expect(ranges.length,3);
    for(final w in ranges){
      expect(w.end.isBefore(w.start),isFalse);
      expect(w.end.difference(w.start).inDays,lessThanOrEqualTo(92));
      expect(w.start.isBefore(DateTime(2026,7,1)),isFalse);
    }
    expect(financeMonth(DateTime(2026,11,20)),'2026-11');
  });

  test('Live metric aggregation balances paid categories and pending bills',(){
    final data=snapshot();
    expect(data.collectedMinor,150000);
    expect(data.pendingMinor,70000);
    expect(data.tuitionMinor,120000);
    expect(data.transportMinor,30000);
    expect(data.otherFeesMinor,0);
    expect(data.salariesMinor,50000);
    expect(data.expensesMinor,30000);
    expect(data.feeReceiptCount,2);
    expect(data.trend.length,6);
    expect(data.trend.singleWhere((x)=>x.month=='2026-10').amountMinor,50000);
    expect(data.trend.singleWhere((x)=>x.month=='2026-11').amountMinor,100000);
    expect(data.transactions.first.reference,'SM-001');
  });

  test('Scope mismatch fails without substituting sample data',(){
    final mismatch=FeePaymentWorkspace(
      schoolId:'another-school',campusId:'campus',yearId:'year',
      yearLabel:'2026-2027',currency:'PKR',canCollect:true,
      years:const[],categories:workspace.categories,students:workspace.students);
    expect(()=>FinanceOverviewSnapshot.fromReports(
      today:DateTime(2026,11,20),workspace:mismatch,
      cashbooks:[cashbook('2026-10-01','2026-11-20')],
      cashflows:[cashflow('2026-10-01','2026-11-20')],
      periodStart:'2026-10-01',periodEnd:'2026-11-20'),throwsStateError);
  });

  testWidgets('Desktop overview mirrors reference layout and quick actions',
      (tester)async{
    await tester.binding.setSurfaceSize(const Size(1510,1000));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final payments=FakeWorkspace(),cash=FakeCashbook(),movement=FakeMovement();
    var expenses=0;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FeeFinancePage(
      owner:owner,setupRepository:FakeSetup(),
      monthlyRepository:FakeMonthly(),paymentRepository:payments,
      cashbookRepository:cash,schoolCashflowRepository:movement,
      selectedCampusId:'campus',onOpenExpenses:()=>expenses++))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-finance-reference-page')),findsOneWidget);
    expect(find.text('Fee & Finance'),findsOneWidget);
    expect(find.byKey(const Key('finance-overview-live')),findsOneWidget);
    expect(find.byKey(const Key('finance-collection-trend-chart')),findsOneWidget);
    expect(find.byKey(const Key('finance-category-donut')),findsOneWidget);
    expect(find.text('Total Collected'),findsOneWidget);
    expect(find.text('Pending Fees'),findsOneWidget);
    expect(find.text('Transport Fees'),findsOneWidget);
    expect(find.text('Salaries (Paid)'),findsOneWidget);
    expect(find.text('Other Expenses'),findsOneWidget);
    expect(payments.reads,greaterThan(0));
    expect(cash.calls,greaterThan(0));
    expect(movement.calls,greaterThan(0));
    final quick=find.byKey(const Key('finance-action-add-expense'));
    await tester.ensureVisible(quick);
    await tester.tap(quick);
    expect(expenses,1);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Reference tabs keep tuition and finance reports accessible',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(1350,900));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FeeFinancePage(
      owner:owner,setupRepository:FakeSetup(),
      monthlyRepository:FakeMonthly(),paymentRepository:FakeWorkspace(),
      cashbookRepository:FakeCashbook(),
      schoolCashflowRepository:FakeMovement()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finance-primary-tab-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-finance-tabs')),findsOneWidget);
    expect(find.text('Fee Setup'),findsWidgets);
    await tester.tap(find.byKey(const Key('finance-primary-tab-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-overview-live')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Mobile overview stacks cards without horizontal overflow',
      (tester)async{
    await tester.binding.setSurfaceSize(const Size(420,920));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    var clicked=false;
    final data=snapshot();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      FinanceOverviewBody(snapshot:data,onCollect:()=>clicked=true,
        onTransport:(){},onSalaries:(){},onAddExpense:(){},
        onInvoice:(){},onReconciliation:(){},onReports:(){},
        onFeeSettings:(){}))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-overview-live')),findsOneWidget);
    expect(find.byKey(const Key('finance-collection-trend-chart')),findsOneWidget);
    final btn=find.byKey(const Key('finance-action-collect-fee'));
    await tester.ensureVisible(btn);
    await tester.pumpAndSettle();
    await tester.tap(btn);
    expect(clicked,isTrue);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Report error never displays fake KPI values',
      (tester)async{
    await tester.binding.setSurfaceSize(const Size(1000,800));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FeeFinancePage(
      owner:owner,setupRepository:FakeSetup(),
      monthlyRepository:FakeMonthly(),
      paymentRepository:FakeWorkspace()..fail=true,
      cashbookRepository:FakeCashbook(),
      schoolCashflowRepository:FakeMovement()))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('finance-overview-retry')),findsOneWidget);
    expect(find.byKey(const Key('finance-overview-live')),findsNothing);
  });
}
