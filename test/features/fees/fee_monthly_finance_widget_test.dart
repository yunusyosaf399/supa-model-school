import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/fees/data/fee_setup_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_monthly_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_finance_page.dart';

const owner = OwnerAccess(
  userId: 'owner-1',displayName: 'School Owner',
  schoolId: 'school-1',schoolName: 'Supa Model School',
  campuses: [OwnerCampus(id: 'campus-1',name: 'Main Campus')],
  activeYearId: 'year-1',activeYearLabel: '2026-2027',
  activeYearStartsOn: '2026-04-01',activeYearEndsOn: '2027-03-31',
  currencyCode: 'PKR',setupComplete: true,
);

class FakeBillingRepository implements FeeMonthlyRepository {
  final calls = <String>[];
  int charged = 0, paid = 0;
  int generated = 0, payments = 0, discounts = 0;
  String? firstGenerateOperation;
  bool failFirstGenerate = false;
  FeeReceipt? receipt;
  String? lastMonth;

  @override Future<FeeMonthlyLedger> load({
    required String schoolId,required String campusId,
    required String yearId,required String month,
  }) async {
    calls.add('load:' + campusId + '/' + month);
    lastMonth = month;
    return FeeMonthlyLedger(
      schoolId: schoolId,campusId: campusId,yearId: yearId,
      month: month,yearLabel: '2026-2027',currency: 'PKR',
      chargedMinor: charged,paidMinor: paid,
      outstandingMinor: charged - paid,receivedMinor: paid,
      students: [
        FeeLedgerStudent(
          id: 'student-1',name: 'Student One',registration: 'SMS-1',
          className: 'Grade 1',active:true,
          chargedMinor: charged,paidMinor:paid,outstandingMinor:charged-paid),
      ],
      categories: const [
        FeeLedgerCategory(
          id:'tuition-1',code:'TUITION',name:'Tuition',
          frequency:'monthly',discountable:true),
      ],
      recentReceipts: [if(receipt != null) receipt!],
    );
  }

  @override Future<FeeStudentStatement> statement({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
  }) async => FeeStudentStatement(
    studentId:studentId,
    charges: [
      if(charged > 0) FeeChargeLine(id:'charge-1',
        month:lastMonth!, category:'Tuition',dueOn:lastMonth!,
        grossMinor:charged,discountMinor:0,
        netMinor:charged,paidMinor:paid),
    ],
    receipts:[if(receipt != null) receipt!],
    discounts:const[],
  );

  @override Future<FeeBillResult> generate({
    required String schoolId,required String campusId,
    required String yearId,required String month,required String operationId,
  }) async {
    calls.add('generate:' + operationId);
    firstGenerateOperation ??= operationId;
    if(failFirstGenerate && generated == 0) {
      failFirstGenerate = false;
      throw StateError('Network unavailable');
    }
    if(generated == 0) { charged = 100050; generated = 1; }
    return FeeBillResult(generated);
  }

  @override Future<FeeReceiptResult> collect({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
    required int amountMinor,required String method,
    String? bankReference,required String operationId,
  }) async {
    if(amountMinor > charged-paid) throw StateError('Overpayment');
    payments++;
    paid += amountMinor;
    receipt = FeeReceipt(id:'receipt-1',number:'SMS-000000001',
      studentId:studentId,studentName:'Student One',
      amountMinor:amountMinor,method:method,issuedAt:'2026-11-18T09:00:00Z',
      bankReference:bankReference);
    calls.add('receipt:' + operationId);
    return FeeReceiptResult('receipt-1','SMS-000000001',amountMinor);
  }

  @override Future<void> grantDiscount({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
    required String categoryId,required String kind,
    int? percentBps,int? fixedMinor,
    required String startMonth,required String reason,
  }) async {
    if(categoryId!='tuition-1'||kind!='percent'||percentBps!=5000) {
      throw StateError('Invalid scholarship in test');
    }
    discounts++;
  }
}

class FakeFeeSetupRepository implements FeeSetupRepository {
  @override Future<FeeSetupSnapshot> load({
    required String schoolId,required String campusId,
    required String academicYearId,
  }) async => FeeSetupSnapshot(
    schoolId:schoolId,campusId:campusId,yearId:academicYearId,
    yearLabel:'2026-2027',currency:'PKR',categories:const[],classes:const[]);
  @override Future<void> createCategory({
    required String schoolId,required String code,required String name,
    required String frequency,required bool discountable,
  }) async {}
  @override Future<void> saveClassPlan({
    required String schoolId,required String campusId,
    required String academicYearId,required String classId,
    required String name,required List<FeePlanLine> items,
  }) async {}
}

Future<void> pumpFinance(WidgetTester tester, FakeBillingRepository repo) async {
  await tester.binding.setSurfaceSize(const Size(440, 880));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: Scaffold(
    body: FeeFinancePage(owner:owner,monthlyRepository:repo,
      setupRepository:FakeFeeSetupRepository()),
  )));
  await tester.pumpAndSettle();
}

void main() {
  test('finance month and operation UUID are normalized', () {
    final today = FeeMonth.normalize(DateTime(2026,11,18));
    expect(today,'2026-11-01');
    expect(FeeMonth.label(today),'November 2026');
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
      .hasMatch(FeeOperationId.create()),isTrue);
    expect(FeeOperationId.create(),isNot(FeeOperationId.create()));
  });

  testWidgets('Monthly Billing loads live student, bills, and records cash receipt',
      (tester) async {
    final repo = FakeBillingRepository();
    await pumpFinance(tester,repo);
    expect(find.byKey(const Key('live-monthly-billing-page')),findsOneWidget);
    expect(find.text('Student One'),findsOneWidget);
    expect(find.text('Not configured'),findsNothing);
    expect(find.byKey(const Key('fee-finance-tabs')),findsOneWidget);

    await tester.tap(find.byKey(const Key('fee-generate-monthly-bills')));
    await tester.pumpAndSettle();
    expect(repo.generated,0);
    await tester.tap(find.byKey(const Key('confirm-generate-bills')));
    await tester.pumpAndSettle();
    expect(repo.generated,1);
    expect(find.textContaining('1000.50'),findsWidgets);

    await tester.tap(find.byKey(const Key('fee-collect-student-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fee-payment-amount')),'250.25');
    await tester.tap(find.byKey(const Key('fee-confirm-payment')));
    await tester.pumpAndSettle();
    expect(repo.payments,1);
    expect(repo.paid,25025);
    expect(find.text('Fee Receipt'),findsOneWidget);
    expect(find.textContaining('SMS-000000001'),findsWidgets);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('749.??'),findsNothing);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Network retry uses same operation ID, no duplicate bills',
    (tester) async {
    final repo = FakeBillingRepository()..failFirstGenerate = true;
    await pumpFinance(tester,repo);
    for (var i=0;i<2;i++) {
      await tester.tap(find.byKey(const Key('fee-generate-monthly-bills')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-generate-bills')));
      await tester.pumpAndSettle();
    }
    expect(repo.generated,1);
    final calls=repo.calls.where((x)=>x.startsWith('generate:')).toList();
    expect(calls.length,2);
    expect(calls[0],calls[1]);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Scholarship is category-specific with precise 50 percent',
    (tester) async {
    final repo=FakeBillingRepository();
    await pumpFinance(tester,repo);
    await tester.tap(find.byKey(const Key('fee-scholarship-student-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fee-discount-value')),'50');
    await tester.enterText(find.byKey(const Key('fee-discount-reason')),
      'Merit scholarship for good performance');
    await tester.tap(find.byKey(const Key('save-fee-discount')));
    await tester.pumpAndSettle();
    expect(repo.discounts,1);
    expect(tester.takeException(),isNull);
  });

  testWidgets('Finance tabs keep fee setup available',
    (tester) async {
    final repo=FakeBillingRepository();
    await pumpFinance(tester,repo);
    await tester.tap(find.text('Fee Setup'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-fee-setup-page')),findsOneWidget);
    expect(tester.takeException(),isNull);
  });
}
