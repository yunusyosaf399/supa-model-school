import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:supa_model_school/features/fees/data/fee_payment_repository.dart';
import 'package:supa_model_school/features/fees/data/fee_detailed_statement.dart';
import 'package:supa_model_school/features/fees/presentation/fee_collection_page.dart';

const student = FeePaymentStudent(
  id: 'student-1', name: 'Areeba Fatima',
  registration: 'SAMPLE-2026-0003',
  classId: 'class-1', className: 'Grade 1',
  sectionId: 'sec-a', sectionName: 'A',
  charges: [
    FeePaymentCharge(
      id: 'charge-transport', categoryId: 'transport',
      categoryName: 'Transport', frequency: 'monthly',
      month: '2026-11-01', dueOn: '2026-11-15',
      netMinor: 6000, paidMinor: 0, outstandingMinor: 6000,
    ),
    FeePaymentCharge(
      id: 'charge-tuition', categoryId: 'tuition',
      categoryName: 'Tuition', frequency: 'monthly',
      month: '2026-11-01', dueOn: '2026-11-30',
      netMinor: 12000, paidMinor: 0, outstandingMinor: 12000,
    ),
  ],
);

FeePaymentWorkspace fixtureWorkspace({bool collect = true}) => FeePaymentWorkspace(
  schoolId: 'school-1', campusId: 'campus-1',
  yearId: 'year-1', yearLabel: '2026-2027',
  currency: 'PKR', canCollect: collect,
  years: const [
    FeeYearChoice('year-1', '2026-2027', true),
    FeeYearChoice('year-0', '2025-2026', false),
  ],
  categories: const [
    FeePaymentCategory(id: 'tuition', code: 'TUITION',
      name: 'Tuition', frequency: 'monthly', active: true),
    FeePaymentCategory(id: 'transport', code: 'TRANSPORT',
      name: 'Transport', frequency: 'monthly', active: true),
    FeePaymentCategory(id: 'annual', code: 'ANNUAL',
      name: 'Annual Resources', frequency: 'yearly', active: true),
    FeePaymentCategory(id: 'admission', code: 'ADMISSION',
      name: 'Admission Fee', frequency: 'one_time', active: true),
  ],
  students: const [student],
);

class FakeFeePaymentRepo implements FeePaymentRepository {
  FakeFeePaymentRepo({this.collectAllowed = true});

  @override
  Future<FeeDetailedStudentLedger> detailedLedger({
    required String schoolId,required String campusId,
    required String yearId,required String studentId,
  })=>throw UnsupportedError('Unused in Quick Pay regression');
  final bool collectAllowed;
  int loads = 0;
  int payments = 0;
  List<QuickPayAllocation>? allocation;
  String? lastStudent, lastMethod, lastOperation;
  @override
  Future<FeePaymentWorkspace> workspace({
    required String schoolId, required String campusId, String? yearId,
  }) async {
    expect(schoolId, 'school-1');
    expect(campusId, 'campus-1');
    loads++;
    return workspaceFixture();
  }

  FeePaymentWorkspace workspaceFixture() =>
    fixtureWorkspace(collect: collectAllowed);

  @override
  Future<QuickPayReceipt> collect({
    required String schoolId, required String campusId,
    required String yearId, required String studentId,
    required int amountMinor, required String method,
    String? bankReference, required String operationId,
    required List<QuickPayAllocation> allocations,
  }) async {
    expect(yearId, 'year-1');
    expect(amountMinor, 10000);
    expect(method, 'cash');
    expect(allocations.length, 2);
    payments++;
    allocation = allocations;
    lastStudent = studentId;
    lastMethod = method;
    lastOperation = operationId;
    return const QuickPayReceipt('receipt-1', 'SMS-000001234', 10000);
  }
}

void main() {
  test('auto pay allocates oldest category first and rejects excess', () {
    final draft = QuickPayPlanner.suggest(
      student, {'tuition', 'transport'}, 10000);
    expect(draft.length, 2);
    expect(draft.first.chargeId, 'charge-transport');
    expect(draft.first.amountMinor, 6000);
    expect(draft.last.amountMinor, 4000);
    QuickPayPlanner.validate(student, 10000, draft);
    expect(() => QuickPayPlanner.suggest(
      student, {'transport'}, 6001), throwsFormatException);
    expect(() => QuickPayPlanner.validate(student, 10000, const [
      QuickPayAllocation(chargeId: 'charge-transport', amountMinor: 5000),
      QuickPayAllocation(chargeId: 'charge-tuition', amountMinor: 4000),
    ]), throwsFormatException);
  });

  testWidgets('finance filters show categories by billing frequency',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1250, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeFeePaymentRepo(collectAllowed: false);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FeeCollectionPage(repository: repo,
        schoolId: 'school-1', campusId: 'campus-1'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fee-collection-live-page')), findsOneWidget);
    expect(find.text('2026-2027'), findsOneWidget);
    expect(find.text('SAMPLE-2026-0003'), findsOneWidget);
    expect(find.byKey(const Key('fee-group-yearly')), findsOneWidget);
    expect(find.byKey(const Key('fee-group-one_time')), findsOneWidget);
    final payButton = tester.widget<FilledButton>(
      find.byKey(const Key('fee-quickpay-SAMPLE-2026-0003')));
    expect(payButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quick Pay review can be manually adjusted before confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeFeePaymentRepo();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      FeeCollectionPage(repository: repo,
        schoolId: 'school-1', campusId: 'campus-1'))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('fee-quickpay-SAMPLE-2026-0003')), 250,
      scrollable: find.byType(Scrollable).first);
    // The Fee Register now has a bulk print action above student accounts.
    // A finder can exist in a lazy list while still being outside the viewport.
    await tester.ensureVisible(
      find.byKey(const Key('fee-quickpay-SAMPLE-2026-0003')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(
      const Key('fee-quickpay-SAMPLE-2026-0003')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('quickpay-page')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('quickpay-amount')), '100.00');
    await tester.scrollUntilVisible(
      find.byKey(const Key('quickpay-preview')), 160,
      scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('quickpay-preview')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('quickpay-line-charge-transport')), 120,
      scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('quickpay-line-charge-transport')),
      findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('quickpay-line-charge-transport')), '50.00');
    await tester.scrollUntilVisible(
      find.byKey(const Key('quickpay-line-charge-tuition')), 120,
      scrollable: find.byType(Scrollable).first);
    await tester.enterText(
      find.byKey(const Key('quickpay-line-charge-tuition')), '50.00');
    await tester.scrollUntilVisible(
      find.byKey(const Key('quickpay-process')), 130,
      scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickpay-process')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('quickpay-confirm-process')));
    await tester.pumpAndSettle();

    expect(repo.payments, 1);
    expect(repo.lastStudent, student.id);
    expect(repo.allocation!.map((row) => row.amountMinor).toList(),
      [5000, 5000]);
    expect(find.textContaining('SMS-000001234'), findsOneWidget);
    expect(find.byKey(const Key('quickpay-print-receipt')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
