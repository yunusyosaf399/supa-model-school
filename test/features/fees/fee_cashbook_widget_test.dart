import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/fee_cashbook_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_cashbook_page.dart';

Map<String,dynamic> exampleReport({
  String? campus='campus-1',
  String method='all',String source='all',
})=> {
  'school_id':'school-1','campus_id':campus,'year_id':'year-1',
  'timezone':'Asia/Karachi','currency':'PKR',
  'from':'2026-11-01','to':'2026-11-18',
  'method':method,'source':source,
  'summary':{
    'amount_minor':15000,'cash_minor':10000,'bank_minor':5000,
    'student_minor':10000,'other_minor':5000,
    'receipt_count':2,'allocation_lines':3,
  },
  'daily':[{
    'date':'2026-11-18','amount_minor':15000,
    'cash_minor':10000,'bank_minor':5000,
    'student_minor':10000,'other_minor':5000,
  }],
  'category_totals':[
    {'id':'cat-tuition','name':'Tuition','frequency':'monthly',
      'amount_minor':6000},
    {'id':'cat-transport','name':'Transport','frequency':'monthly',
      'amount_minor':9000},
  ],
  'entries':[
    {
      'source':'student','receipt_id':'receipt-1',
      'receipt_no':'SMS-000000123','campus_id':'campus-1',
      'date':'2026-11-18','method':'cash',
      'payer_name':'SAMPLE Areeba','payer_reference':'SAMPLE-0001',
      'class_id':'class-1','class_name':'Grade 1',
      'category_id':'cat-tuition','category':'Tuition',
      'amount_minor':6000,
    },
    {
      'source':'student','receipt_id':'receipt-1',
      'receipt_no':'SMS-000000123','campus_id':'campus-1',
      'date':'2026-11-18','method':'cash',
      'payer_name':'SAMPLE Areeba','payer_reference':'SAMPLE-0001',
      'class_id':'class-1','class_name':'Grade 1',
      'category_id':'cat-transport','category':'Transport',
      'amount_minor':4000,
    },
    {
      'source':'other','receipt_id':'receipt-2',
      'receipt_no':'SMS-000000124','campus_id':'campus-1',
      'date':'2026-11-18','method':'bank',
      'payer_name':"=HYPERLINK('bad')",
      'payer_reference':'TEST',
      'class_id':null,'class_name':null,
      'category_id':'cat-transport','category':'Transport',
      'amount_minor':5000,
    },
  ],
  'year_options':[{'id':'year-1','label':'2026-27'}],
  'campus_options':[{'id':'campus-1','name':'Main Campus'}],
  'category_options':[
    {'id':'cat-tuition','name':'Tuition'},
    {'id':'cat-transport','name':'Transport'},
  ],
  'class_options':[{'id':'class-1','name':'Grade 1',
      'campus_id':'campus-1'}],
  'unbalanced_receipts':0,
};
class FakeReportRepository implements FeeCashbookRepository {
  FakeReportRepository({this.fail=false});
  final bool fail;
  int calls=0;
  String? lastCampus,lastYear,lastMethod,lastSource,lastCategory,lastClass;
  @override
  Future<FeeCashbookReport> load({
    required String schoolId,required String yearId,
    required String from,required String to,
    required String method,required String source,
    String? campusId,String? categoryId,String? classId,
  }) async {
    calls++;
    lastCampus=campusId;lastYear=yearId;
    lastMethod=method;lastSource=source;
    lastCategory=categoryId;lastClass=classId;
    if(fail)throw StateError('Fee viewing permission required');
    final result=exampleReport(campus:campusId,method:method,source:source);
    result['from']=from;result['to']=to;
    return FeeCashbookReport.fromJson(result);
  }
}

void main(){
  test('fee income totals do not double count split receipts',(){
    final report=FeeCashbookReport.fromJson(exampleReport());
    expect(report.summary.amountMinor,15000);
    expect(report.summary.cashMinor+report.summary.bankMinor,15000);
    expect(report.summary.studentMinor+report.summary.otherMinor,15000);
    expect(report.summary.receiptCount,2);
    expect(report.summary.allocationLines,3);
    expect(report.entries.length,3);
    expect(report.entries.where((e)=>e.receiptNo=='SMS-000000123')
      .fold<int>(0,(a,e)=>a+e.amountMinor),10000);
    expect(report.daily.single.amountMinor,15000);
    expect(report.categoryTotals.fold<int>(0,(a,c)=>a+c.amountMinor),15000);
    expect(report.summary.totalsReconcile,isTrue);
    expect(report.unbalancedReceipts,0);
    final csv=report.toCsv();
    expect(csv.contains('SMS-000000123'),isTrue);
    expect(csv.contains('''"'=HYPERLINK('bad')""'),isTrue);
  });

  testWidgets('cashbook shows totals and filters by source and method',
    (tester)async {
    await tester.binding.setSurfaceSize(const Size(1260,950));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeReportRepository();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FeeCashbookPage(
      repository:repo,schoolId:'school-1',yearId:'year-1',
      initialCampusId:'campus-1'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-cashbook-live-page')),findsOneWidget);
    expect(find.text('Fee Income & Collection Cashbook'),findsOneWidget);
    expect(find.text('PKR 150.00'),findsWidgets);
    expect(find.textContaining('2 distinct receipts'),findsOneWidget);
    expect(find.byKey(const Key('fee-cashbook-copy-csv')),findsOneWidget);
    expect(find.byKey(const Key('fee-cashbook-day-2026-11-18')),
      findsOneWidget);
    await tester.tap(find.byKey(const Key('fee-cashbook-source')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other payers').last);
    await tester.pumpAndSettle();
    expect(repo.lastSource,'other');
    expect(repo.lastCampus,'campus-1');
    expect(tester.takeException(),isNull);
  });

  testWidgets('Owner can select entire school; staff cannot',
    (tester)async {
    await tester.binding.setSurfaceSize(const Size(1180,920));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeReportRepository();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FeeCashbookPage(
      repository:repo,schoolId:'school-1',yearId:'year-1',
      initialCampusId:'campus-1',allowAllCampuses:true))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-cashbook-campus')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All campuses').last);
    await tester.pumpAndSettle();
    expect(repo.lastCampus,isNull);
    expect(tester.takeException(),isNull);
  });

  testWidgets('access-denied report does not display financial values',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000,820));
    addTearDown(()=>tester.binding.setSurfaceSize(null));
    final repo=FakeReportRepository(fail:true);
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:FeeCashbookPage(
      repository:repo,schoolId:'school-1',yearId:'year-1',
      initialCampusId:'campus-1'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fee viewing permission required'),findsOneWidget);
    expect(find.text('PKR 150.00'),findsNothing);
    expect(find.byKey(const Key('fee-cashbook-copy-csv')),findsNothing);
    expect(tester.takeException(),isNull);
  });
}
