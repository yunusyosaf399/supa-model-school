import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/owner_auth_gateway.dart';
import 'package:supa_model_school/features/dashboard/data/dashboard_repository.dart';
import 'package:supa_model_school/features/dashboard/presentation/dashboard_page.dart';

class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository(this.result);
  DashboardSnapshot result;
  final queries = <String>[];

  @override
  Future<DashboardSnapshot> load({
    required String schoolId, required String campusId,
  }) async {
    queries.add('$schoolId/$campusId');
    return result;
  }
}

const owner = OwnerAccess(
  userId: 'verified-fixture-owner',
  displayName: 'Demo Test Owner',
  schoolId: 'school-id',
  schoolName: 'Supa Model School',
  setupComplete: true,
  campuses: [
    OwnerCampus(id: 'campus-a', name: 'Main Campus'),
    OwnerCampus(id: 'campus-b', name: 'Junior Campus'),
  ],
  activeYearLabel: '2026–2027',
  activeYearId: 'year-id',
);

Widget dashboard(FakeDashboardRepository repo, {String campus = 'campus-a'}) =>
    MaterialApp(home: Scaffold(body: DashboardPage(
      owner: owner, repository: repo, selectedCampusId: campus,
      onNewAdmission: () {}, onStudents: () {}, onFees: () {},
      onAttendance: () {}, onExpenses: () {},
      onCampusChanged: (_) {},
    )));

void main() {
  test('dashboard snapshot parses nullable real metrics and test fixtures', () {
    final demo = DashboardSnapshot.preview();
    expect(demo.isDemo, isTrue);
    expect(demo.activeStudents, 1248);
    expect(demo.recentAdmissions, hasLength(4));
    final live = DashboardSnapshot.fromJson({
      'is_demo': false, 'school_name': 'School',
      'campus_name': 'Campus', 'year_label': '2026–2027',
      'currency_code': 'PKR', 'active_students': 11,
      'fee_collected': null, 'attendance_total': null,
      'recent_admissions': [], 'fee_trend': [],
      'pending_admissions': 0,
    });
    expect(live.isDemo, isFalse);
    expect(live.feeCollected, isNull);
    expect(live.attendanceTotal, isNull);
    expect(live.pendingAdmissions, 0);
  });

  testWidgets('desktop dashboard follows reference and uses scoped RPC data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 950));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final repo = FakeDashboardRepository(DashboardSnapshot.preview());
    await tester.pumpWidget(dashboard(repo));
    await tester.pumpAndSettle();
    expect(repo.queries, ['school-id/campus-a']);
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-demo-banner')), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Active Students'), findsOneWidget);
    expect(find.text('Fee Collection Trend'), findsOneWidget);
    expect(find.text('Recent Admissions'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-new-admission')), findsOneWidget);
  });

  testWidgets('mobile dashboard shows reference cards and bottom-friendly layout',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 890));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final repo = FakeDashboardRepository(DashboardSnapshot.preview());
    await tester.pumpWidget(dashboard(repo));
    await tester.pumpAndSettle();
    expect(find.text('Good morning,'), findsOneWidget);
    expect(find.text('Supa Model School'), findsOneWidget);
    expect(find.text('Collect\nFee'), findsOneWidget);
    expect(find.text('Attendance'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-demo-banner')), findsOneWidget);
    expect(repo.queries, ['school-id/campus-a']);
  });

  testWidgets('live dashboard never fabricates finance and attendance values',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 950));
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final repo = FakeDashboardRepository(DashboardSnapshot.fromJson({
      'is_demo': false,
      'source': 'live_db02_summary',
      'school_name': 'Supa Model School',
      'campus_name': 'Main Campus',
      'year_label': '2026–2027',
      'currency_code': 'PKR',
      'active_students': 0,
      'pending_admissions': 0,
      'fee_collected': null,
      'fees_outstanding': null,
      'attendance_total': null,
      'attendance_present': null,
      'recent_admissions': [],
      'fee_trend': [],
    }));
    await tester.pumpWidget(dashboard(repo));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-demo-banner')), findsNothing);
    expect(find.text('Fee ledger has not been deployed.'), findsOneWidget);
    expect(find.text('Attendance records are not configured.'), findsOneWidget);
    expect(find.text('No approved admissions in the active school year.'),
        findsOneWidget);
  });
}
