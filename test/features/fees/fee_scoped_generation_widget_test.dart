import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/fee_billing_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_scoped_generation_page.dart';

const a=FeePaymentStudent(id:'s1',name:'SAMPLE Ayesha',
  registration:'SAMP-001',classId:'c1',className:'Grade 4',
  sectionId:'secA',sectionName:'A',charges:[]);
const b=FeePaymentStudent(id:'s2',name:'SAMPLE Bilal',
  registration:'SAMP-002',classId:'c1',className:'Grade 4',
  sectionId:'secA',sectionName:'A',charges:[]);
const c=FeePaymentStudent(id:'s3',name:'SAMPLE Hamza',
  registration:'SAMP-003',classId:'c2',className:'Grade 5',
  sectionId:'secB',sectionName:'B',charges:[]);
const tuition=FeePaymentCategory(
  id:'tuition',code:'TUITION',name:'Tuition',frequency:'monthly',active:true);
const transport=FeePaymentCategory(
  id:'transport',code:'TRANSPORT',name:'Transport',frequency:'monthly',active:true);
const workspace=FeePaymentWorkspace(
  schoolId:'school-1',campusId:'campus-1',yearId:'year-1',
  yearLabel:'2026–2027',currency:'PKR',canCollect:true,
  years:[FeeYearChoice('year-1','2026-2027',true)],
  categories:[tuition,transport],
  students:[a,b,c]);

class FakeScopedRepository extends FeeBillingRepository {
  int calls=0;
  String? scope,section,operation;
  List<String>? selected,categories;
  bool failFirst=false;
  final operationHistory=<String>[];

  @override
  Future<ScopedBillResult> generateScoped({
    required String schoolId,required String campusId,required String yearId,
    required String month,required List<String> categoryIds,
    required String scope,String? sectionId,List<String> studentIds=const [],
    required bool includeOptional,required String operationId,
  }) async{
    expect(schoolId,'school-1');
    expect(campusId,'campus-1');
    expect(yearId,'year-1');
    expect(month,'2026-11-01');
    calls++;
    this.scope=scope;section=sectionId;
    selected=studentIds;categories=categoryIds;
    operation=operationId;operationHistory.add(operationId);
    if(failFirst){
      failFirst=false;
      throw StateError('Connection interrupted');
    }
    return ScopedBillResult(
      scope:scope,students:scope=='section'?2:studentIds.length,
      added:scope=='section'?2:studentIds.length,
      skipped:0,eligible:scope=='section'?2:studentIds.length,
      categories:[
        for(final id in categoryIds)
          BatchBillCategory(name:id,frequency:'monthly',
            added:scope=='section'?2:studentIds.length,skipped:0),
      ]);
  }
}

Future<void> show(FakeScopedRepository repo,WidgetTester tester)async{
  await tester.binding.setSurfaceSize(const Size(1000,1250));
  addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:FeeScopedGenerationPage(
    repository:repo,workspace:workspace,initialMonth:'2026-11-01')));
  await tester.pumpAndSettle();
}
Future<void> confirm(WidgetTester tester) async{
  final process=find.byKey(const Key('fee-scoped-process'));
  await tester.ensureVisible(process);
  await tester.tap(process);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('fee-scoped-confirm')),findsOneWidget);
  await tester.tap(find.byKey(const Key('fee-scoped-confirm')));
  await tester.pumpAndSettle();
}

void main(){
  test('Scoped RPC parsing fails closed on unconfirmed result',(){
    expect(()=>ScopedBillResult.fromJson({'saved':false}),throwsStateError);
    final result=ScopedBillResult.fromJson({
      'saved':true,'mode':'scoped','scope':'section',
      'student_count':2,'added_charges':2,
      'skipped_existing':1,'eligible_charges':3,
      'categories':[{
        'category':'Tuition','frequency':'monthly',
        'added_charges':2,'skipped_existing':1,
      }]
    });
    expect(result.added,2);
    expect(result.students,2);
  });

  testWidgets('section mode generates class-plan fees only for section',
    (tester)async{
    final repo=FakeScopedRepository();
    await show(repo,tester);
    await tester.tap(find.byKey(const Key('fee-scoped-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 4 — A').last);
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(repo.calls,1);
    expect(repo.scope,'section');
    expect(repo.section,'secA');
    expect(repo.selected,isEmpty);
    expect(repo.categories,['tuition']);
    expect(find.textContaining('2 new fees'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('selected mode bills only checked students, across classes',
    (tester)async{
    final repo=FakeScopedRepository();
    await show(repo,tester);
    await tester.tap(find.text('Selected students'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-scoped-student-SAMP-001')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-scoped-student-SAMP-003')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('fee-scoped-category-TRANSPORT')));
    await tester.tap(find.byKey(const Key('fee-scoped-category-TRANSPORT')));
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(repo.calls,1);
    expect(repo.scope,'selected');
    expect(repo.section,isNull);
    expect(repo.selected?.toSet(),{'s1','s3'});
    expect(repo.categories,['tuition','transport']);
    expect(tester.takeException(),isNull);
  });

  testWidgets('empty student selection is rejected without server call',
    (tester)async{
    final repo=FakeScopedRepository();
    await show(repo,tester);
    await tester.tap(find.text('Selected students'));
    await tester.pumpAndSettle();
    final submit=find.byKey(const Key('fee-scoped-process'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repo.calls,0);
    expect(find.textContaining('Choose a valid month'),findsOneWidget);
  });

  testWidgets('retry keeps operation ID after server response failure',
    (tester)async{
    final repo=FakeScopedRepository()..failFirst=true;
    await show(repo,tester);
    await tester.tap(find.byKey(const Key('fee-scoped-section')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grade 4 — A').last);
    await tester.pumpAndSettle();
    await confirm(tester);
    expect(repo.calls,1);
    final retry=find.byKey(const Key('fee-scoped-process'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repo.calls,2);
    expect(repo.operationHistory[0],repo.operationHistory[1]);
    expect(find.text('Fees generated successfully'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
