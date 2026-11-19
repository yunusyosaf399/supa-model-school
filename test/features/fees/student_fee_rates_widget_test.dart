import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/fees/data/fee_setup_repository.dart';
import 'package:supa_model_school/features/fees/presentation/student_fee_rates_page.dart';

const st=StudentFeeRateStudent(id:'student-1',name:'SAMPLE Sara',
  registration:'SAMPLE-2026-1',classId:'class-1',
  className:'Grade One',sectionName:'A');
const cat=StudentFeeRateCategory(
  id:'category-1',name:'Tuition',code:'TUITION',frequency:'monthly');
const setup=FeeSetupSnapshot(schoolId:'school',campusId:'campus',
  yearId:'year',yearLabel:'2026-27',currency:'PKR',
  categories:[
    FeeCategory(id:'category-1',code:'TUITION',name:'Tuition',
      frequency:'monthly',discountable:true,active:true)],
  classes:[
    ClassFeeSummary(id:'class-1',name:'Grade One',sortOrder:1,
      plan:ClassFeePlan(id:'plan',name:'Grade One Plan',version:1,
        status:'active',effectiveFrom:'2026-07-01',
        lines:[FeePlanLine(categoryId:'category-1',amountMinor:100000)]))]);

class RateSaveCall{
  RateSaveCall(this.student,this.category,this.kind,this.amount,
    this.start,this.end,this.reason,this.op);
  final String student,category,kind,start,reason,op;
  final String? end;
  final int? amount;
}
class FakeRates implements FeeSetupRepository {
  final saves=<RateSaveCall>[];
  final rules=<StudentFeeRateRule>[];
  bool failFirst=false;
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);

  @override
  Future<StudentFeeRatesSnapshot> loadStudentRates({
    required String schoolId,required String campusId,required String yearId,
  })async{
    expect(schoolId,'school');
    expect(campusId,'campus');
    expect(yearId,'year');
    return StudentFeeRatesSnapshot(schoolId:schoolId,campusId:campusId,
      yearId:yearId,currency:'PKR',students:[st],categories:[cat],rules:rules);
  }

  @override
  Future<void> saveStudentRate({
    required String schoolId,required String campusId,required String yearId,
    required String studentId,required String categoryId,required String kind,
    int? amountMinor,required String startMonth,String? endMonth,
    required String reason,required String operationId,
  })async{
    saves.add(RateSaveCall(studentId,categoryId,kind,amountMinor,
      startMonth,endMonth,reason,operationId));
    if(failFirst){failFirst=false;throw Exception('connection interrupted');}
    for(var i=0;i<rules.length;i++){
      final r=rules[i];
      if(r.active){rules[i]=StudentFeeRateRule(
        id:r.id,studentId:r.studentId,categoryId:r.categoryId,
        kind:r.kind,amountMinor:r.amountMinor,startMonth:r.startMonth,
        endMonth:r.endMonth,reason:r.reason,active:false);}
    }
    rules.insert(0,StudentFeeRateRule(id:'rate-'+saves.length.toString(),
      studentId:studentId,categoryId:categoryId,kind:kind,
      amountMinor:amountMinor,startMonth:startMonth,endMonth:endMonth,
      reason:reason,active:true));
  }
}

Future<void> pumpRates(WidgetTester tester,FakeRates repo)async{
  await tester.binding.setSurfaceSize(const Size(940,1120));
  addTearDown(()=>tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home:StudentFeeRatesPage(
    repository:repo,plans:setup,schoolId:'school',campusId:'campus',
    yearId:'year',yearLabel:'2026-27')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('student-rate-student')));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('SAMPLE Sara').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('student-rate-start')),'2026-11');
}
Future<void> commit(WidgetTester tester)async{
  final save=find.byKey(const Key('student-rate-save'));
  await tester.ensureVisible(save);
  await tester.tap(save);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('student-rate-confirm')));
  await tester.pumpAndSettle();
}

void main(){
  test('student rate snapshot validates required structure',(){
    final r=StudentFeeRatesSnapshot.fromJson({
      'school_id':'a','campus_id':'b','year_id':'y','currency':'PKR',
      'students':[],
      'categories':[],
      'rules':[],
    });
    expect(r.students,isEmpty);
    expect(()=>StudentFeeRatesSnapshot.fromJson({
      'school_id':'a','campus_id':'b','year_id':'y','currency':'PKR',
      'students':null,'categories':[],'rules':[],
    }),throwsFormatException);
  });

  testWidgets('Owner saves an individual monthly Tuition rate',
    (tester)async{
    final repo=FakeRates();
    await pumpRates(tester,repo);
    expect(find.textContaining('PKR 1000.00'),findsWidgets);
    await tester.enterText(find.byKey(const Key('student-rate-amount')),'850.00');
    await tester.enterText(find.byKey(const Key('student-rate-reason')),
      'Special approved rate for this student');
    await commit(tester);
    expect(repo.saves.length,1);
    expect(repo.saves.first.student,'student-1');
    expect(repo.saves.first.category,'category-1');
    expect(repo.saves.first.kind,'override');
    expect(repo.saves.first.amount,85000);
    expect(repo.saves.first.start,'2026-11-01');
    expect(find.byKey(const Key('student-rate-current')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Owner can exempt a student without a custom amount',
    (tester)async{
    final repo=FakeRates();
    await pumpRates(tester,repo);
    await tester.tap(find.byKey(const Key('student-rate-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exempt from this fee').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('student-rate-amount')),findsNothing);
    await tester.enterText(find.byKey(const Key('student-rate-reason')),
      'Scholarship fully covers tuition');
    await commit(tester);
    expect(repo.saves.single.kind,'exempt');
    expect(repo.saves.single.amount,isNull);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Owner can restore standard class rate', (tester)async{
    final repo=FakeRates();
    await pumpRates(tester,repo);
    await tester.tap(find.byKey(const Key('student-rate-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore class standard rate').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('student-rate-reason')),
      'Student returns to normal class tuition');
    await commit(tester);
    expect(repo.saves.single.kind,'standard');
    expect(repo.saves.single.amount,isNull);
    expect(repo.saves.single.end,isNull);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Unconfirmed save retries the exact same operation', (tester)async{
    final repo=FakeRates()..failFirst=true;
    await pumpRates(tester,repo);
    await tester.enterText(find.byKey(const Key('student-rate-amount')),'950.00');
    await tester.enterText(find.byKey(const Key('student-rate-reason')),
      'One student fee adjustment only');
    await commit(tester);
    expect(repo.saves.length,1);
    expect(find.textContaining('Save not confirmed'),findsOneWidget);
    final retry=find.byKey(const Key('student-rate-save'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repo.saves.length,2);
    expect(repo.saves.first.op,repo.saves.last.op);
    expect(find.byKey(const Key('student-rate-saved')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Zero individual rate is rejected without posting', (tester)async{
    final repo=FakeRates();
    await pumpRates(tester,repo);
    await tester.enterText(find.byKey(const Key('student-rate-amount')),'0');
    await tester.enterText(find.byKey(const Key('student-rate-reason')),
      'Invalid zero rate is forbidden');
    final btn=find.byKey(const Key('student-rate-save'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(repo.saves,isEmpty);
    expect(find.textContaining('positive amount'),findsOneWidget);
  });
}
