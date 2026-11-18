import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/school_cashflow_repository.dart';
import 'package:supa_model_school/features/fees/presentation/school_cashflow_page.dart';

Map<String,dynamic> cashflowFixture({
 String? campus='campus-1',required String from,required String to,
})=> {
 'school_id':'school-1','year_id':'year-1','campus_id':campus,
 'from':from,'to':to,'timezone':'Asia/Karachi','currency':'PKR',
 'summary':{
   'inflow_minor':3657200,'outflow_minor':120000,
   'net_movement_minor':3537200,
   'student_fee_minor':855000,'other_fee_minor':2802200,
   'canteen_minor':0,'uniform_minor':0,'expense_minor':120000,
   'salary_minor':0,'fee_refund_minor':0,
   'cash_in_minor':3197200,'bank_in_minor':460000,
   'cash_out_minor':120000,'bank_out_minor':0,
   'transaction_lines':3,
 },
 'entries':[
   {'date':'2026-11-18','source':'student','kind':'fee',
    'reference':'SMS-123','counterparty':'Sample School Child',
    'category':'Tuition','method':'cash','signed_minor':855000},
   {'date':'2026-11-18','source':'other','kind':'fee',
    'reference':'SMS-124','counterparty':"=HYPERLINK('test')",
    'category':'Resources','method':'cash','signed_minor':2802200},
   {'date':'2026-11-18','source':'expense','kind':'outflow',
    'reference':'EXP-001','counterparty':'Demo Vendor',
    'category':'Repairs','method':'cash','signed_minor':-120000},
 ],
 'daily':[
   {'date':'2026-11-18','inflow_minor':3657200,
    'outflow_minor':120000,'net_minor':3537200},
 ],
 'cancelled_retail_minor':500,'cancelled_retail_count':1,
 'direct_stock_cost_minor':0,
 'pending_expense_requests':2,'unbalanced_fee_receipts':0,
 'scope_note':'Posted financial activity, not net profit.',
 'campus_options':[{'id':'campus-1','name':'Main Campus'}],
 'year_options':[{'id':'year-1','label':'2026-2027',
    'starts_on':'2026-04-01','ends_on':'2027-03-31'}],
};
class FakeCashflowRepo implements SchoolCashflowRepository {
  FakeCashflowRepo({this.denied=false});
  final bool denied;
  int calls=0;
  String? lastCampus;
  @override
  Future<SchoolCashflowReport> load({
    required String schoolId,required String yearId,
    String? campusId,required String from,required String to})async {
    calls++;lastCampus=campusId;
    expect(schoolId,'school-1');expect(yearId,'year-1');
    if(denied)throw StateError('Verified School Owner required');
    return SchoolCashflowReport.fromJson(
      cashflowFixture(campus:campusId,from:from,to:to));
  }
}

void main(){
  test('posted amounts reconcile; outflows are not confused with profit',(){
    final report=SchoolCashflowReport.fromJson(cashflowFixture(
      from:'2026-11-01',to:'2026-11-18'));
    final s=report.summary;
    expect(s.reconciles,isTrue);
    expect(s.inflowMinor,3657200);
    expect(s.netMinor,3537200);
    expect(s.studentFeeMinor+s.otherFeeMinor,3657200);
    expect(s.outflowMinor,120000);
    expect(s.salaryMinor,0);
    expect(report.cancelledRetailMinor,500);
    expect(report.pendingExpenseRequests,2);
    final csv=report.toCsv();
    expect(csv.contains("SMS-123"),isTrue);
    expect(csv.contains("'=HYPERLINK"),isTrue,
      reason:'Do not copy untrusted spreadsheet formulas unescaped');
    expect(csv.contains('1200.00'),isTrue);
  });

  testWidgets('Owner dashboard displays reconciled amounts and limitations',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(1280,920));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeCashflowRepo();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      SchoolCashflowPage(repository:repo,schoolId:'school-1',
        yearId:'year-1',initialCampusId:'campus-1'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('school-cashflow-page')),findsOneWidget);
    expect(find.text('School Cash Movement'),findsOneWidget);
    expect(find.text('PKR 36572.00'),findsWidgets);
    expect(find.text('PKR 1200.00'),findsWidgets);
    expect(find.text('Posted transaction amounts reconcile'),findsOneWidget);
    expect(find.textContaining('NOT net profit'),findsOneWidget);
    expect(find.byKey(const Key('school-cashflow-copy-csv')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Owner all-campus selection is propagated to repository',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(1150,890));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeCashflowRepo();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      SchoolCashflowPage(repository:repo,schoolId:'school-1',
        yearId:'year-1',initialCampusId:'campus-1'))));
    await tester.pumpAndSettle();
    expect(repo.lastCampus,'campus-1');
    await tester.tap(find.byKey(const Key('school-cashflow-campus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Campuses').last);
    await tester.pumpAndSettle();
    expect(repo.lastCampus,isNull);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Denied owner report displays no financial amounts',
    (tester)async{
    await tester.binding.setSurfaceSize(const Size(920,740));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeCashflowRepo(denied:true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:
      SchoolCashflowPage(repository:repo,schoolId:'school-1',
        yearId:'year-1',initialCampusId:'campus-1'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Verified School Owner required'),findsOneWidget);
    expect(find.byKey(const Key('school-cashflow-copy-csv')),findsNothing);
    expect(find.text('PKR 36572.00'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
