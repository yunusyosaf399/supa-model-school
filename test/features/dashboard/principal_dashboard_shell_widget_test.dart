import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supa_model_school/features/auth/data/principal_auth_gateway.dart';
import 'package:supa_model_school/features/auth/data/staff_permission_gateway.dart';
import 'package:supa_model_school/features/dashboard/data/dashboard_repository.dart';
import 'package:supa_model_school/features/admissions/data/admission_approval_repository.dart';
import 'package:supa_model_school/features/admissions/presentation/principal_dashboard_shell.dart';
import 'package:supa_model_school/features/students/data/student_directory_repository.dart';
import 'package:supa_model_school/features/students/models/student_directory.dart';

const principal = PrincipalAccess(
  userId: 'principal-test', displayName: 'TEST Principal',
  schoolId: 'school-1', schoolName: 'Supa Model School',
  campuses: [PrincipalCampus(id: 'campus-1', name: 'Main Campus')],
);

class TestPermissions extends StaffPermissionGateway {
  const TestPermissions(this.codes);
  final Set<String> codes;
  @override Future<Set<String>> allowedActions() async => codes;
}

class TestPrincipalDashboard extends DashboardRepository {
  final calls = <String>[];
  @override
  Future<DashboardSnapshot> load({
    required String schoolId, required String campusId,
  }) async {
    calls.add('$schoolId/$campusId');
    if (schoolId != 'school-1' || campusId != 'campus-1') {
      throw StateError('Wrong campus');
    }
    return DashboardSnapshot.fromJson({
      'is_demo': false, 'source': 'live_principal_campus_summary',
      'school_name': 'Supa Model School',
      'campus_name': 'Main Campus',
      'year_label': '2026–2027', 'currency_code': 'PKR',
      'active_students': 32, 'pending_admissions': 1,
      'fee_collected': null, 'fees_outstanding': null,
      'recent_admissions': <Object>[], 'fee_trend': <Object>[],
    });
  }
}

class TestPrincipalStudents extends StudentDirectoryRepository {
  final calls = <String>[];
  @override Future<StudentDirectoryProjection> load({
    required String schoolId, required String campusId,
  }) async {
    calls.add('$schoolId/$campusId');
    return StudentDirectoryProjection(
      authorizedCampusIds: {campusId},
      records: const <StudentSummary>[],
    );
  }
}

class TestApprovals extends AdmissionApprovalRepository {
  final calls = <String>[];
  @override Future<List<PrincipalApprovalItem>> listPending({
    required String schoolId, required String campusId,
  }) async {
    calls.add('$schoolId/$campusId');
    return const [];
  }
  @override Future<AdmissionSubmitResult> submit(AdmissionSubmitRequest request) =>
    throw UnsupportedError('Owner-only');
  @override Future<PrincipalDecisionResult> review({
    required String applicationId, required int expectedRevision,
    required String operationId, required String decision, String? reason,
  }) => throw UnsupportedError('No mutation in dashboard');
  @override Future<List<PrincipalDocumentRecord>> listDocuments(String id) =>
    throw UnsupportedError('No document in dashboard');
  @override Future<String> signedDocumentUrl(PrincipalDocumentRecord doc) =>
    throw UnsupportedError('No download in dashboard');
  @override Future<void> reviewDocument({
    required String documentId, required int expectedRevision,
    required String operationId, required String decision, String? reason,
  }) => throw UnsupportedError('No mutation in dashboard');
}

Widget shell({
  required TestPermissions permissions,
  required TestPrincipalDashboard dashboard,
  required TestApprovals approvals,
  required TestPrincipalStudents students,
}) => MaterialApp(home: PrincipalDashboardShell(
  principal: principal,
  permissionGateway: permissions,
  dashboardRepository: dashboard,
  approvalRepository: approvals,
  studentRepository: students,
  onSignOut: () async {},
));

void main() {
  testWidgets('Principal has Owner-style mobile dashboard and authorized tabs',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dashboard = TestPrincipalDashboard();
    final approvals = TestApprovals();
    final students = TestPrincipalStudents();
    await tester.pumpWidget(shell(
      permissions: const TestPermissions({
        'dashboard.read', 'students.read', 'admissions.review',
      }),
      dashboard: dashboard, approvals: approvals, students: students,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-mobile-greeting')), findsOneWidget);
    expect(find.byKey(const Key('principal-mobile-navigation')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-demo-banner')), findsNothing);
    expect(find.text('Active Students'), findsOneWidget);
    expect(dashboard.calls, ['school-1/campus-1']);
    expect(find.text('Collect Fee'), findsNothing);
    expect(find.text('New Admission'), findsNothing);
    await tester.tap(find.byKey(const Key('principal-nav-2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('principal-approval-page')), findsOneWidget);
    expect(approvals.calls, ['school-1/campus-1']);
    await tester.tap(find.byKey(const Key('principal-nav-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('student-directory')), findsOneWidget);
    expect(students.calls, ['school-1/campus-1']);
    await tester.tap(find.byKey(const Key('principal-nav-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
  });

  testWidgets('revoked dashboard.read never exposes a preview or Home tab',
    (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dashboard = TestPrincipalDashboard();
    final approvals = TestApprovals();
    final students = TestPrincipalStudents();
    await tester.pumpWidget(shell(
      permissions: const TestPermissions({'admissions.review'}),
      dashboard: dashboard, approvals: approvals, students: students,
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('dashboard-page')), findsNothing);
    expect(find.byKey(const Key('dashboard-demo-banner')), findsNothing);
    expect(find.byKey(const Key('principal-nav-0')), findsNothing);
    expect(find.byKey(const Key('principal-nav-1')), findsNothing);
    expect(find.byKey(const Key('principal-approval-page')), findsOneWidget);
    expect(dashboard.calls, isEmpty);
  });

  testWidgets('desktop Principal dashboard uses same dashboard widgets',
    (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1440, 960);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final dashboard = TestPrincipalDashboard();
    await tester.pumpWidget(shell(
      permissions: const TestPermissions({
        'dashboard.read', 'admissions.review',
      }),
      dashboard: dashboard,
      approvals: TestApprovals(), students: TestPrincipalStudents(),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('principal-desktop-navigation')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-page')), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.byKey(const Key('dashboard-pending-approvals')), findsOneWidget);
    expect(find.byKey(const Key('dashboard-fee-trend')), findsNothing);
    expect(find.byKey(const Key('dashboard-recent-admissions')), findsNothing);
    expect(find.byKey(const Key('dashboard-demo-banner')), findsNothing);
    expect(dashboard.calls, ['school-1/campus-1']);
  });
}
