import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

import 'package:supa_model_school/features/fees/data/fee_demand_slip.dart';
import 'package:supa_model_school/features/fees/data/fee_detailed_statement.dart';
import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_bulk_demand_slips_page.dart';
import 'package:supa_model_school/features/fees/presentation/fee_demand_slip_pdf.dart';

FeePaymentCharge charge(String id,String category,String month,
  int net,int paid,{String frequency='monthly'})=>FeePaymentCharge(
    id:id,categoryId:category.toLowerCase(),categoryName:category,
    frequency:frequency,month:month,dueOn:month.substring(0,7)+'-27',
    netMinor:net,paidMinor:paid,outstandingMinor:net-paid);

FeePaymentWorkspace example({bool updated=false})=>FeePaymentWorkspace(
  schoolId:'school',campusId:'campus',yearId:'year',
  yearLabel:'2026-2027',currency:'PKR',canCollect:false,
  years:const [FeeYearChoice('year','2026-2027',true)],
  categories:const [
    FeePaymentCategory(id:'tuition',code:'TUITION',name:'Tuition',
      frequency:'monthly',active:true),
    FeePaymentCategory(id:'transport',code:'TRANSPORT',name:'Transport',
      frequency:'monthly',active:true),
  ],
  students:[
    FeePaymentStudent(
      id:'a',name:'SAMPLE Ayesha',registration:'SAMPLE-A',
      classId:'grade1',className:'Grade One',sectionId:'secA',
      sectionName:'A',charges:[
        charge('c1','Tuition','2026-11-01',10000,updated?2500:2000),
        charge('c2','Transport','2026-11-01',3000,
          updated?500:0),
        charge('c3','Tuition','2026-10-01',5000,1000),
      ]),
    FeePaymentStudent(
      id:'b',name:'SAMPLE Bilal',registration:'SAMPLE-B',
      classId:'grade1',className:'Grade One',sectionId:'secB',
      sectionName:'B',charges:[
        charge('c4','Tuition','2026-11-01',9000,9000),
        charge('c5','Exam','2026-10-01',2000,1000),
      ]),
    FeePaymentStudent(
      id:'c',name:'SAMPLE Hamza',registration:'SAMPLE-C',
      classId:'grade2',className:'Grade Two',sectionId:'secC',
      sectionName:'C',charges:[
        charge('c6','Tuition','2026-11-01',7000,0),
      ]),
  ],
);

class DemandRepo implements FeePaymentRepository {
  DemandRepo({this.changedAfterFirst=false});
  final bool changedAfterFirst;
  int loads=0;
  @override
  dynamic noSuchMethod(Invocation call)=>super.noSuchMethod(call);
  @override
  Future<FeePaymentWorkspace> workspace({
    required String schoolId,required String campusId,String? yearId,
  })async{
    expect(schoolId,'school');expect(campusId,'campus');
    expect(yearId,'year');
    loads++;
    return example(updated:changedAfterFirst&&loads>=2);
  }
  @override
  Future<FeeDetailedStudentLedger> detailedLedger({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
  })=>throw UnsupportedError('Not used for bulk demand slips');
}

Future<void> mount(WidgetTester tester,DemandRepo repository,
    {bool arrears=true})async{
  await tester.binding.setSurfaceSize(const Size(1024,1100));
  addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:FeeBulkDemandSlipsPage(
    repository:repository,initialWorkspace:example(),
    initialClassId:'grade1',initialMonth:'2026-11')));
  await tester.pumpAndSettle();
}

void main(){
  test('Class and section monthly notices contain only unpaid posted items',(){
    final w=example();
    final all=FeeDemandBatch.build(workspace:w,
      month:'2026-11',classId:'grade1');
    expect(all.students.length,2);
    expect(all.currentDueMinor,11000);
    expect(all.arrearsDueMinor,5000);
    expect(all.totalDueMinor,16000);
    expect(all.students.first.name,'SAMPLE Ayesha');
    expect(all.students.last.name,'SAMPLE Bilal');
    expect(all.students.last.currentDueMinor,0);
    expect(all.students.first.lines.length,3);
    expect(all.students.last.lines.length,1);
    final section=FeeDemandBatch.build(workspace:w,
      month:'2026-11',classId:'grade1',sectionId:'secA');
    expect(section.students.length,1);
    expect(section.students.single.totalDueMinor,15000);
    expect(section.sectionName,'A');
    final noArrears=FeeDemandBatch.build(workspace:w,
      month:'2026-11',classId:'grade1',includeArrears:false);
    expect(noArrears.students.length,1);
    expect(noArrears.totalDueMinor,11000);
    expect(noArrears.arrearsDueMinor,0);
    expect(noArrears.students.single.registration,'SAMPLE-A');
    final other=FeeDemandBatch.build(workspace:w,
      month:'2026-11',classId:'grade2');
    expect(other.students.single.registration,'SAMPLE-C');
    expect(other.totalDueMinor,7000);
  });

  test('Class selection, cross-section and invalid months fail closed',(){
    final w=example();
    expect(()=>FeeDemandBatch.build(workspace:w,
      month:'2026-11',classId:''),throwsFormatException);
    expect(()=>FeeDemandBatch.build(workspace:w,
      month:'2026-13',classId:'grade1'),throwsFormatException);
    expect(()=>FeeDemandBatch.build(workspace:w,
      month:'2026-11',classId:'grade1',sectionId:'secC'),
      throwsFormatException);
    final f=example();
    f.students.first.charges.first; // Posted values remain read-only.
    expect(f.students.first.charges.first.outstandingMinor,8000);
  });

  test('Dual-copy batch PDF is generated without recording a payment',()async{
    final b=FeeDemandBatch.build(workspace:example(),month:'2026-11',
      classId:'grade1',generatedAtUtc:DateTime.utc(2026,11,20,12));
    final both=await FeeDemandSlipPdf.build(b,PdfPageFormat.a4);
    final student=await FeeDemandSlipPdf.build(
      b,PdfPageFormat.a4,copy:'student');
    final office=await FeeDemandSlipPdf.build(
      b,PdfPageFormat.a4,copy:'office');
    for(final bytes in [both,student,office]){
      expect(bytes.length,greaterThan(900));
      expect(ascii.decode(bytes.sublist(0,5)),'%PDF-');
    }
    expect(both.length,greaterThan(student.length));
    expect(both.length,greaterThan(office.length));
    expect(FeeDemandSlipPdf.build(b,PdfPageFormat.a4,copy:'bad'),
      throwsFormatException);
    final noDue=FeeDemandBatch.build(workspace:example(),
      month:'2026-09',classId:'grade1');
    expect(noDue.students,isEmpty);
    expect(FeeDemandSlipPdf.build(noDue,PdfPageFormat.a4),
      throwsFormatException);
  });

  testWidgets('Read-only user can preview class demand slips and change arrears',
    (tester)async{
    final repo=DemandRepo();
    await mount(tester,repo);
    expect(repo.loads,1);
    expect(find.byKey(const Key('bulk-fee-demand-page')),findsOneWidget);
    expect(find.byKey(const Key('bulk-demand-student-SAMPLE-A')),findsOneWidget);
    expect(find.byKey(const Key('bulk-demand-student-SAMPLE-B')),findsOneWidget);
    expect(find.byKey(const Key('bulk-demand-print-both')),findsOneWidget);
    final checkbox=find.byKey(const Key('bulk-demand-include-arrears'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bulk-demand-student-SAMPLE-B')),findsNothing);
    expect(find.byKey(const Key('bulk-demand-student-SAMPLE-A')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Fresh changes block printing and request another review',
    (tester)async{
    final repo=DemandRepo(changedAfterFirst:true);
    await mount(tester,repo);
    final btn=find.byKey(const Key('bulk-demand-print-both'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(repo.loads,2);
    expect(find.textContaining('Student balances changed'),findsOneWidget);
    expect(find.byKey(const Key('bulk-demand-confirm')),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Unchanged balances require user confirmation before printing',
    (tester)async{
    final repo=DemandRepo();
    await mount(tester,repo);
    final btn=find.byKey(const Key('bulk-demand-print-both'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(repo.loads,2);
    expect(find.byKey(const Key('bulk-demand-confirm')),findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(),isNull);
  });
}
