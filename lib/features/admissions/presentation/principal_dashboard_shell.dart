import 'package:flutter/material.dart';
import '../../auth/data/principal_auth_gateway.dart';
import '../../auth/data/staff_permission_gateway.dart';
import '../../auth/data/account_password_gateway.dart';
import '../../auth/presentation/account_password_page.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../dashboard/presentation/dashboard_page.dart';
import '../../owner/data/school_logo_service.dart';
import '../../exams/data/exam_repository.dart';
import '../../exams/presentation/exam_management_page.dart';
import '../../fees/data/fee_payment_repository.dart';
import '../../fees/presentation/fee_collection_page.dart';
import '../../students/data/student_directory_repository.dart';
import '../../students/presentation/student_directory_page.dart';
import '../data/admission_approval_repository.dart';
import 'principal_approval_page.dart';
import '../../../ui/school_brand.dart';

/// Owner-style dashboard with exclusively Principal-scoped RPCs and navigation.
class PrincipalDashboardShell extends StatefulWidget {
  const PrincipalDashboardShell({
    super.key, required this.principal, required this.dashboardRepository,
    required this.approvalRepository, required this.permissionGateway,
    required this.onSignOut, this.studentRepository, this.examRepository,
    this.logoService, this.passwordGateway, this.feePaymentRepository,
  });

  final PrincipalAccess principal;
  final DashboardRepository dashboardRepository;
  final AdmissionApprovalRepository approvalRepository;
  final StaffPermissionGateway permissionGateway;
  final StudentDirectoryRepository? studentRepository;
  final ExamRepository? examRepository;
  final FeePaymentRepository? feePaymentRepository;
  final SchoolLogoService? logoService;
  final AccountPasswordGateway? passwordGateway;
  final Future<void> Function() onSignOut;

  @override
  State<PrincipalDashboardShell> createState() => _PrincipalDashboardShellState();
}

class _PrincipalDashboardShellState extends State<PrincipalDashboardShell> {
  late String _campusId;
  Future<Set<String>>? _permissions;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _campusId = widget.principal.campuses.first.id;
    _permissions = widget.permissionGateway.allowedActions();
    widget.logoService?.load(widget.principal.logoStoragePath);
  }

  @override
  void didUpdateWidget(covariant PrincipalDashboardShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.principal.userId != widget.principal.userId ||
        oldWidget.permissionGateway != widget.permissionGateway) {
      _campusId = widget.principal.campuses.first.id;
      _selected = 0;
      _permissions = widget.permissionGateway.allowedActions();
      widget.logoService?.load(widget.principal.logoStoragePath);
    }
  }

  void _reload() {
    setState(() {
      _permissions = widget.permissionGateway.allowedActions();
    });
  }

  void _changeCampus(String campusId) {
    if (!widget.principal.campuses.any((c) => c.id == campusId)) return;
    setState(() => _campusId = campusId);
  }

  List<(int, String, IconData)> _sections(Set<String> grants) => [
    if (grants.contains('dashboard.read'))
      (0, 'Home', Icons.home_rounded),
    if (grants.contains('students.read') &&
        widget.studentRepository != null)
      (1, 'Students', Icons.groups_outlined),
    if (grants.contains('admissions.review'))
      (2, 'Approvals', Icons.fact_check_outlined),
    if (grants.contains('exams.read') && widget.examRepository != null)
      (4, 'Examinations', Icons.fact_check_outlined),
    if (grants.contains('fees.read') && widget.feePaymentRepository != null)
      (5, 'Fees', Icons.payments_outlined),
    (3, 'Account', Icons.manage_accounts_outlined),
  ];

  Widget _page(int active, Set<String> grants) {
    switch (active) {
      case 0:
        return DashboardPage(
          key: ValueKey('principal-dashboard-' + _campusId),
          principal: widget.principal,
          allowedActions: grants,
          selectedCampusId: _campusId,
          onCampusChanged: _changeCampus,
          repository: widget.dashboardRepository,
          logoService: widget.logoService,
          onNewAdmission: () {},
          onStudents: () => setState(() => _selected = 1),
          onAdmissions: () => setState(() => _selected = 2),
          onFees: () {}, onAttendance: () {}, onExpenses: () {},
          onExit: () { widget.onSignOut(); },
        );
      case 1:
        return StudentDirectoryPage(
          key: ValueKey('principal-students-' + _campusId),
          onNewAdmission: () {},
          allowNewAdmission: false,
          staffSchoolId: widget.principal.schoolId,
          staffCampusId: _campusId,
          repository: widget.studentRepository,
        );
      case 2:
        return PrincipalApprovalPage(
          key: ValueKey('principal-queue-' + _campusId),
          schoolId: widget.principal.schoolId,
          campusId: _campusId,
          repository: widget.approvalRepository,
        );
      case 5:
        return FeeCollectionPage(
          key: ValueKey('principal-fees-' + _campusId),
          repository: widget.feePaymentRepository!,
          schoolId: widget.principal.schoolId,
          campusId: _campusId,
        );
      case 4:
        return ExamManagementPage(
          key: ValueKey('principal-exams-$_campusId'),
          repository: widget.examRepository!,
          schoolId: widget.principal.schoolId,
          campusId: _campusId,
          canCreate: grants.contains('exams.create'),
          canUpdate: grants.contains('exams.update'),
        );
      default:
        return widget.passwordGateway == null
          ? const Center(child: Text('Account settings unavailable.'))
          : AccountPasswordPage(
              gateway: widget.passwordGateway!,
              onPasswordChanged: widget.onSignOut,
            );
    }
  }

  Widget _sidebar(List<(int, String, IconData)> sections,
      int active, bool extended) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Container(
      key: const Key('principal-desktop-navigation'),
      width: extended ? 248 : 68,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(
          right: BorderSide(color: Color(0xFFDDE8ED))),
      ),
      child: Column(children: [
        if (extended) Padding(
          padding: const EdgeInsets.fromLTRB(9, 13, 9, 13),
          child: Column(children: [
            SchoolMark(size: 77, logoService: widget.logoService),
            const SizedBox(height: 4),
            Text(widget.principal.schoolName,
              textAlign: TextAlign.center, maxLines: 2,
              style: TextStyle(color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 3),
            Text('Principal • ' + widget.principal.displayName,
              textAlign: TextAlign.center,
              style: TextStyle(color: ink, fontSize: 11)),
            const SizedBox(height: 10),
            const Divider(height: 1),
          ]),
        ) else const SizedBox(height: 18),
        Expanded(child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          children: [
            for (final section in sections) Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: section.$1 == active
                      ? const LinearGradient(colors: [
                          Color(0xFF079989), Color(0xFF005651),
                        ]) : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: InkWell(
                    key: Key('principal-nav-' + section.$1.toString()),
                    onTap: () => setState(() => _selected = section.$1),
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(height: 42,
                      child: Row(children: [
                        const SizedBox(width: 12),
                        Icon(section.$3, size: 21,
                          color: section.$1 == active ? Colors.white : ink),
                        if (extended) ...[
                          const SizedBox(width: 13),
                          Expanded(child: Text(section.$2, style: TextStyle(
                            color: section.$1 == active ? Colors.white : ink,
                            fontWeight: section.$1 == active
                              ? FontWeight.w800 : FontWeight.w500,
                            fontSize: 13))),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        )),
        IconButton(
          key: const Key('principal-reload-permissions'),
          tooltip: 'Refresh assigned permissions',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
        TextButton.icon(
          key: const Key('principal-sign-out'),
          onPressed: () { widget.onSignOut(); },
          icon: const Icon(Icons.logout_outlined),
          label: extended ? const Text('Sign out') : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }

  Widget _mobileNavigation(
      List<(int, String, IconData)> sections, int active) {
    return SafeArea(top: false,
      child: Container(
        key: const Key('principal-mobile-navigation'),
        height: 66,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFD7E3E8))),
        ),
        child: Row(children: [
          for (final section in sections)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: section.$1 == active
                      ? const LinearGradient(colors: [
                          Color(0xFF008D7E), Color(0xFF00534F),
                        ]) : null,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: InkWell(
                    key: Key('principal-nav-' + section.$1.toString()),
                    onTap: () => setState(() => _selected = section.$1),
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(section.$3, size: 24,
                          color: section.$1 == active
                            ? Colors.white : const Color(0xFF53626D)),
                        const SizedBox(height: 3),
                        Text(section.$2, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: section.$1 == active
                              ? Colors.white : const Color(0xFF53626D),
                            fontSize: 11,
                            fontWeight: section.$1 == active
                              ? FontWeight.w800 : FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            )),
        ]),
      ),
    );
  }

  Widget _contentShell(Set<String> grants) {
    final sections = _sections(grants);
    final active = sections.any((s) => s.$1 == _selected)
      ? _selected : sections.first.$1;
    final desktop = MediaQuery.sizeOf(context).width >= 860;
    final extended = MediaQuery.sizeOf(context).width >= 1190;

    return Scaffold(
      key: const Key('principal-dashboard-shell'),
      appBar: active == 0 ? null : AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.principal.schoolName,
              style: Theme.of(context).textTheme.titleMedium),
            Text('Principal • ' + widget.principal.displayName,
              style: Theme.of(context).textTheme.bodySmall),
          ]),
        actions: [
          if (widget.principal.campuses.length > 1)
            DropdownButton<String>(
              key: const Key('principal-campus-selector'),
              value: _campusId,
              items: [
                for (final campus in widget.principal.campuses)
                  DropdownMenuItem(
                    value: campus.id, child: Text(campus.name)),
              ],
              onChanged: (campus) {
                if (campus != null) _changeCampus(campus);
              },
            ),
          IconButton(
            key: const Key('principal-refresh'),
            tooltip: 'Refresh permissions',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            key: const Key('principal-sign-out'),
            tooltip: 'Sign out',
            onPressed: () { widget.onSignOut(); },
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: SafeArea(top: !desktop, bottom: false,
        child: desktop ? Row(children: [
          _sidebar(sections, active, extended),
          const VerticalDivider(width: 1),
          Expanded(child: _page(active, grants)),
        ]) : _page(active, grants),
      ),
      bottomNavigationBar: desktop
        ? null : _mobileNavigation(sections, active),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Set<String>>(
    future: _permissions,
    builder: (context, snapshot) {
      if (snapshot.hasError) return Scaffold(
        key: const Key('principal-dashboard-shell'),
        body: SafeArea(child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Cannot load this account’s permissions.'),
            TextButton(
              onPressed: _reload, child: const Text('Retry')),
          ]),
        )),
      );
      if (!snapshot.hasData) return const Scaffold(
        key: Key('principal-dashboard-shell'),
        body: Center(child: CircularProgressIndicator()),
      );
      return _contentShell(snapshot.data!);
    },
  );
}
