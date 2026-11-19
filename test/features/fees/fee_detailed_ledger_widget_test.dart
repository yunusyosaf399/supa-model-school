import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:supa_model_school/features/fees/data/fee_detailed_statement.dart';
import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_detailed_ledger_page.dart';
import 'package:supa_model_school/features/fees/presentation/fee_statement_pdf.dart';
import 'package:supa_model_school/features/fees/presentation/fee_billing_reports_page.dart';

Map<String,dynamic> fixture(){
 Map<String,dynamic> group(String label,String id,int gross,int discount,
     int net,int paid,int due){
   return {
     if(id=='month')'month':label,
     if(id!='month')'category':label,
     if(id!='month')'category_id':id,
     if(id!='month')'frequency':'monthly',
     'charge_count':1,'gross_minor':gross,'discount_minor':discount,
     'net_minor':net,'paid_minor':paid,'outstanding_minor':due,
   };
 }
 Map<String,dynamic> charge(String id,String category,String catId,
     String month,int gross,int discount,int paid,int due){
   return {
     'id':id,'category_id':catId,'category':category,
     'frequency':'monthly','month':month,'due_on':month.substring(0,7)+'-28',
     'source_kind':'manual','description':category+' charge',
     'posted_at':month+'T09:00:00Z',
     'gross_minor':gross,'discount_minor':discount,
     'net_minor':gross-discount,'paid_minor':paid,
     'outstanding_minor':due,
   };
 }
 return {
  'school_id':'school','campus_id':'campus','year_id':'year',
  'student_id':'st1','school_name':'Supa Model School',
  'year_label':'2026-2027','student_name':'SAMPLE Student A',
  'registration':'TEST-001','class_name':'Grade 2',
  'section_name':'A','currency':'PKR',
  'totals':{
    'charge_count':2,'gross_minor':16000,'discount_minor':1000,
    'net_minor':15000,'paid_minor':10000,'outstanding_minor':5000,
    'receipt_count':2,
  },
  'months':[
    group('2026-10-01','month',10000,1000,9000,7000,2000),
    group('2026-11-01','month',6000,0,6000,3000,3000),
  ],
  'categories':[
    group('Tuition','tuition',10000,1000,9000,7000,2000),
    group('Transport','transport',6000,0,6000,3000,3000),
  ],
  'charges':[
    charge('ct','Tuition','tuition','2026-10-01',
      10000,1000,7000,2000),
    charge('cr','Transport','transport','2026-11-01',
      6000,0,3000,3000),
  ],
  'receipts':[
    {'id':'r1','number':'SAMPLE-REC-1','receipt_total_minor':8500,
      'allocated_to_year_minor':8500,'method':'cash',
      'issued_at':'2026-11-02T10:00:00Z','bank_reference':null},
    {'id':'r2','number':'SAMPLE-REC-2','receipt_total_minor':1500,
      'allocated_to_year_minor':1500,'method':'bank',
      'issued_at':'2026-11-03T10:00:00Z','bank_reference':'TEST-REF'},
  ],
  'allocations':[
    {'id':'a1','charge_id':'ct','receipt_id':'r1',
      'receipt_no':'SAMPLE-REC-1','category':'Tuition',
      'month':'2026-10-01','amount_minor':5500,'payment_method':'cash',
      'issued_at':'2026-11-02T10:00:00Z'},
    {'id':'a2','charge_id':'cr','receipt_id':'r1',
      'receipt_no':'SAMPLE-REC-1','category':'Transport',
      'month':'2026-11-01','amount_minor':3000,'payment_method':'cash',
      'issued_at':'2026-11-02T10:00:00Z'},
    {'id':'a3','charge_id':'ct','receipt_id':'r2',
      'receipt_no':'SAMPLE-REC-2','category':'Tuition',
      'month':'2026-10-01','amount_minor':1500,'payment_method':'bank',
      'issued_at':'2026-11-03T10:00:00Z'},
  ],
 };
}
const student=FeePaymentStudent(id:'st1',name:'SAMPLE Student A',
 registration:'TEST-001',classId:'class1',className:'Grade 2',
 sectionId:'sec1',sectionName:'A',charges:[
   FeePaymentCharge(id:'ct',categoryId:'tuition',categoryName:'Tuition',
     frequency:'monthly',month:'2026-10-01',dueOn:'2026-10-28',
     netMinor:9000,paidMinor:7000,outstandingMinor:2000),
   FeePaymentCharge(id:'cr',categoryId:'transport',categoryName:'Transport',
     frequency:'monthly',month:'2026-11-01',dueOn:'2026-11-28',
     netMinor:6000,paidMinor:3000,outstandingMinor:3000),
 ]);
const workspace=FeePaymentWorkspace(
 schoolId:'school',campusId:'campus',yearId:'year',
 yearLabel:'2026-2027',currency:'PKR',canCollect:true,
 years:[FeeYearChoice('year','2026-2027',true)],
 categories:[
   FeePaymentCategory(id:'tuition',code:'TUITION',name:'Tuition',
     frequency:'monthly',active:true),
   FeePaymentCategory(id:'transport',code:'TRANSPORT',name:'Transport',
     frequency:'monthly',active:true),
 ],
 students:[student],
);
class FakeLedgerRepo implements FeePaymentRepository{
 int calls=0;
 @override
 dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
 @override
 Future<FeeDetailedStudentLedger> detailedLedger({
   required String schoolId,required String campusId,
   required String yearId,required String studentId,
 })async{
   expect(schoolId,'school');expect(campusId,'campus');
   expect(yearId,'year');expect(studentId,'st1');
   calls++;
   return FeeDetailedStudentLedger.fromJson(fixture());
 }
}

void main(){
 test('statement reconciles partial receipts, categories and months',(){
   final report=FeeDetailedStudentLedger.fromJson(fixture());
   expect(report.totals.net,15000);
   expect(report.totals.paid,10000);
   expect(report.totals.outstanding,5000);
   expect(report.months.length,2);
   expect(report.categories.singleWhere((c)=>c.id=='tuition').totals.paid,7000);
   expect(report.receipts.first.yearAllocated,8500);
   final csv=report.chargesCsv();
   expect(csv,contains('"Tuition"'));
   expect(csv,contains('"Individual Student"'),isFalse);
 });

 test('fails closed on mismatched charge allocation',(){
   final x=fixture();
   (x['allocations'] as List)[0]['amount_minor']=5499;
   expect(()=>FeeDetailedStudentLedger.fromJson(x),throwsFormatException);
 });
 test('fails closed on mismatched monthly sums',(){
   final x=fixture();
   (x['months'] as List)[0]['paid_minor']=7001;
   (x['months'] as List)[0]['outstanding_minor']=1999;
   expect(()=>FeeDetailedStudentLedger.fromJson(x),throwsFormatException);
 });

 test('PDF statement generates valid bytes on A4',()async{
   final report=FeeDetailedStudentLedger.fromJson(fixture());
   final bytes=await FeeStatementPdf.build(report,PdfPageFormat.a4);
   expect(bytes.length,greaterThan(150));
   expect(ascii.decode(bytes.sublist(0,5)),'%PDF-');
 });

 testWidgets('student ledger displays charges, allocated receipts and filters',
   (tester)async{
   await tester.binding.setSurfaceSize(const Size(1000,1200));
   addTearDown(()=>tester.binding.setSurfaceSize(null));
   final repo=FakeLedgerRepo();
   await tester.pumpWidget(MaterialApp(home:FeeDetailedLedgerPage(
     repository:repo,workspace:workspace,student:student)));
   await tester.pumpAndSettle();
   expect(repo.calls,1);
   expect(find.byKey(const Key('student-ledger-print')),findsOneWidget);
   expect(find.byKey(const Key('student-ledger-copy-csv')),findsOneWidget);
   expect(find.byKey(const Key('student-ledger-charge-ct')),findsOneWidget);
   expect(find.byKey(const Key('student-ledger-charge-cr')),findsOneWidget);
   final month=find.byKey(const Key('student-ledger-month-filter'));
   await tester.ensureVisible(month);
   await tester.tap(month);
   await tester.pumpAndSettle();
   await tester.tap(find.text('2026-10').last);
   await tester.pumpAndSettle();
   expect(find.byKey(const Key('student-ledger-charge-cr')),findsNothing);
   expect(find.byKey(const Key('student-ledger-charge-ct')),findsOneWidget);
   expect(tester.takeException(),isNull);
 });

 testWidgets('billing report aggregates due by class/category and month',
   (tester)async{
   await tester.binding.setSurfaceSize(const Size(1050,1100));
   addTearDown(()=>tester.binding.setSurfaceSize(null));
   await tester.pumpWidget(const MaterialApp(
     home:FeeBillingReportsPage(workspace:workspace)));
   await tester.pumpAndSettle();
   expect(find.byKey(const Key('billing-report-print')),findsOneWidget);
   expect(find.text('PKR 50.00'),findsWidgets);
   expect(find.text('Category Totals'),findsOneWidget);
   expect(find.text('Monthly Totals'),findsOneWidget);
   expect(find.text('Class Totals'),findsOneWidget);
   expect(tester.takeException(),isNull);
 });
}
