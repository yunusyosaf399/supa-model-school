import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/fees/data/fee_setup_repository.dart';
import 'package:supa_model_school/features/fees/presentation/fee_setup_page.dart';

const owner = OwnerAccess(
  userId: 'test-owner', displayName: 'Test Owner',
  schoolId: 'school-1', schoolName: 'Supa Model School',
  setupComplete: true, activeYearId: 'year-1',
  activeYearLabel: '2026-2027', currencyCode: 'PKR',
  campuses: [OwnerCampus(id: 'campus-1', name: 'Main Campus')],
);

class FakeFeeRepository implements FeeSetupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
  final calls = <String>[];
  FeeCategory? category;
  ClassFeePlan? plan;
  bool denyWrite = false;

  @override
  Future<FeeSetupSnapshot> load({
    required String schoolId, required String campusId,
    required String academicYearId,
  }) async {
    calls.add('read:$schoolId/$campusId/$academicYearId');
    return FeeSetupSnapshot(schoolId: schoolId,campusId: campusId,
      yearId: academicYearId,yearLabel: '2026-2027',currency: 'PKR',
      categories: category == null ? const [] : [category!],
      classes: [ClassFeeSummary(
        id: 'grade-1', name: 'Grade 1', sortOrder: 1, plan: plan)],
    );
  }

  @override
  Future<void> createCategory({
    required String schoolId,required String code,required String name,
    required String frequency,required bool discountable,
  }) async {
    if (denyWrite) throw StateError('Write denied');
    calls.add('category:$schoolId/$code');
    category = FeeCategory(id:'category-1',code:code,name:name,
      frequency:frequency,discountable:discountable,active:true);
  }

  @override
  Future<void> saveClassPlan({
    required String schoolId,required String campusId,
    required String academicYearId,required String classId,
    required String name,required List<FeePlanLine> items,
  }) async {
    if (denyWrite) throw StateError('Write denied');
    calls.add('plan:$schoolId/$campusId/$academicYearId/$classId');
    plan = ClassFeePlan(id:'plan-1',name:name,version:1,status:'active',
      effectiveFrom:'2026-11-18',lines:items);
  }
}

void main() {
  test('fee money uses exact cents and rejects invalid money', () {
    expect(FeeMoney.parseMinor('1000'), 100000);
    expect(FeeMoney.parseMinor('1000.50'), 100050);
    expect(FeeMoney.parseMinor('0.1'), 10);
    expect(FeeMoney.parseMinor('1.001'), isNull);
    expect(FeeMoney.parseMinor('-1'), isNull);
    expect(FeeMoney.parseMinor('abc'), isNull);
    expect(FeeMoney.showMinor(100050), '1000.50');
  });

  testWidgets('Owner can configure a category and real class plan',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeFeeRepository();
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FeeSetupPage(owner: owner, repository: repo,
        selectedCampusId: 'campus-1'))));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('live-fee-setup-page')),findsOneWidget);
    expect(find.text('No plan configured'),findsOneWidget);
    expect(repo.calls, ['read:school-1/campus-1/year-1']);
    await tester.tap(find.byKey(const Key('fee-add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fee-category-name')), 'Tuition Fee');
    await tester.enterText(find.byKey(const Key('fee-category-code')), 'TUITION');
    await tester.tap(find.byKey(const Key('save-fee-category')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('category:school-1/TUITION'));
    expect(find.textContaining('Tuition Fee'),findsWidgets);
    await tester.tap(find.byKey(const Key('fee-configure-grade-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-category-select-TUITION')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fee-amount-TUITION')), '1000.50');
    await tester.tap(find.byKey(const Key('save-class-fee-plan')));
    await tester.pumpAndSettle();
    expect(repo.plan!.lines.single.amountMinor, 100050);
    expect(find.text('PKR 1000.50'),findsOneWidget);
    expect(find.text('Version 1 • Effective 2026-11-18'),findsOneWidget);
    expect(tester.takeException(),isNull);
  });

  testWidgets('backend refusal never displays a fake saved plan',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repo = FakeFeeRepository()..denyWrite = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: FeeSetupPage(owner: owner, repository: repo))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee-add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('fee-category-name')), 'Tuition Fee');
    await tester.enterText(find.byKey(const Key('fee-category-code')), 'TUITION');
    await tester.tap(find.byKey(const Key('save-fee-category')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Write denied'),findsOneWidget);
    expect(repo.category,isNull);
    expect(repo.plan,isNull);
    expect(tester.takeException(),isNull);
  });
}
