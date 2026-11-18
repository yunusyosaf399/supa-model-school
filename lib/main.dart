import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/data/owner_auth_gateway.dart';
import 'features/auth/data/principal_auth_gateway.dart';
import 'features/auth/data/staff_auth_gateway.dart';
import 'features/auth/data/staff_permission_gateway.dart';
import 'features/auth/data/account_password_gateway.dart';
import 'features/auth/presentation/staff_account_home.dart';
import 'features/admissions/presentation/principal_admissions_home.dart';
import 'config/supabase_connection_config.dart';

import 'features/admissions/presentation/admission_wizard_page.dart';
import 'features/admissions/presentation/admission_draft_list_page.dart';
import 'features/admissions/data/admission_draft_repository.dart';
import 'features/admissions/data/admission_document_service.dart';
import 'features/admissions/data/admission_approval_repository.dart';
import 'features/academics/data/academic_structure_repository.dart';
import 'features/academics/presentation/academic_structure_page.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/dashboard/presentation/dashboard_visuals.dart';
import 'features/dashboard/data/dashboard_repository.dart';
import 'features/owner/presentation/owner_control_panel_page.dart';
import 'features/owner/data/owner_user_management_repository.dart';
import 'features/owner/data/school_logo_service.dart';
import 'features/students/presentation/student_directory_page.dart';
import 'features/students/data/student_directory_repository.dart';
import 'features/fees/data/fee_setup_repository.dart';
import 'features/fees/presentation/fee_setup_page.dart';
import 'features/fees/data/fee_monthly_repository.dart';
import 'features/fees/data/fee_payment_repository.dart';
import 'features/fees/data/fee_billing_repository.dart';
import 'features/fees/data/fee_cashbook_repository.dart';
import 'features/fees/data/school_cashflow_repository.dart';
import 'features/exams/data/exam_repository.dart';
import 'features/exams/presentation/exam_management_page.dart';
import 'features/fees/presentation/fee_finance_page.dart';
import 'features/operations/data/owner_operations_repository.dart';
import 'features/operations/presentation/owner_staff_directory_page.dart';
import 'features/operations/presentation/owner_transport_directory_page.dart';
import 'features/attendance/data/attendance_repository.dart';
import 'features/attendance/presentation/owner_attendance_setup_page.dart';
import 'ui/school_brand.dart';
import 'ui/school_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Debug launches connect to the existing test project automatically.
  // Release builds require explicit --dart-define public credentials.
  SupabaseConnectionConfig.validate();
  const url = SupabaseConnectionConfig.projectUrl;
  const key = SupabaseConnectionConfig.publishableKey;
  OwnerAuthGateway gateway = const UnconfiguredOwnerAuthGateway();
  AcademicStructureRepository academicRepo =
      const UnconfiguredAcademicStructureRepository();
  DashboardRepository dashboardRepo = const UnconfiguredDashboardRepository();
  DashboardRepository? principalDashboardRepo;
  StudentDirectoryRepository? studentRepo;
  FeeSetupRepository? feeSetupRepo;
  FeeMonthlyRepository? feeMonthlyRepo;
  FeePaymentRepository? feePaymentRepo;
  FeeBillingRepository? feeBillingRepo;
  FeeCashbookRepository? feeCashbookRepo;
  SchoolCashflowRepository? schoolCashflowRepo;
  OwnerOperationsRepository? operationsRepo;
  ExamRepository? examRepo;
  AttendanceRepository? attendanceRepo;
  StudentDirectoryRepository? staffStudentRepo;
  AdmissionDraftRepository? admissionRepo;
  AdmissionDocumentService? documentService;
  AdmissionApprovalRepository? approvalRepo;
  OwnerUserManagementRepository? ownerUsersRepo;
  SchoolLogoService? logoService;
  PrincipalAuthGateway principalAuth = const UnconfiguredPrincipalAuthGateway();
  StaffAuthGateway staffAuth = const UnconfiguredStaffAuthGateway();
  StaffPermissionGateway? staffPermissions;
  AccountPasswordGateway? staffPasswordGateway;
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      // Session tokens must not be persisted in unencrypted preferences.
      // Enable persistence only after a secure per-device storage adapter
      // and revocation/recovery tests have been implemented.
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
    gateway = SupabaseOwnerAuthGateway(Supabase.instance.client);
    academicRepo = SupabaseAcademicStructureRepository(Supabase.instance.client);
    dashboardRepo = SupabaseDashboardRepository(Supabase.instance.client);
    principalDashboardRepo = SupabasePrincipalDashboardRepository(Supabase.instance.client);
    studentRepo = SupabaseStudentDirectoryRepository(Supabase.instance.client);
    feeSetupRepo = SupabaseFeeSetupRepository(Supabase.instance.client);
    feeMonthlyRepo = SupabaseFeeMonthlyRepository(Supabase.instance.client);
    feePaymentRepo = SupabaseFeePaymentRepository(Supabase.instance.client);
    feeBillingRepo = SupabaseFeeBillingRepository(Supabase.instance.client);
    feeCashbookRepo = SupabaseFeeCashbookRepository(Supabase.instance.client);
    schoolCashflowRepo = SupabaseSchoolCashflowRepository(Supabase.instance.client);
    operationsRepo = SupabaseOwnerOperationsRepository(Supabase.instance.client);
    examRepo = SupabaseExamRepository(Supabase.instance.client);
    attendanceRepo = SupabaseAttendanceRepository(Supabase.instance.client);
    staffStudentRepo = SupabaseStaffStudentDirectoryRepository(Supabase.instance.client);
    admissionRepo = SupabaseAdmissionDraftRepository(Supabase.instance.client);
    documentService = SupabaseAdmissionDocumentService(Supabase.instance.client);
    approvalRepo = SupabaseAdmissionApprovalRepository(Supabase.instance.client);
    ownerUsersRepo = SupabaseOwnerUserManagementRepository(Supabase.instance.client);
    logoService = SchoolLogoService(Supabase.instance.client);
    principalAuth = SupabasePrincipalAuthGateway(Supabase.instance.client);
    staffAuth = SupabaseStaffAuthGateway(Supabase.instance.client);
    staffPermissions = SupabaseStaffPermissionGateway(Supabase.instance.client);
    staffPasswordGateway = SupabaseAccountPasswordGateway(Supabase.instance.client);
  }
  runApp(SupaModelSchoolApp(
    authGateway: gateway,
    academicRepository: academicRepo,
    dashboardRepository: dashboardRepo,
    principalDashboardRepository: principalDashboardRepo,
    studentDirectoryRepository: studentRepo,
    feeSetupRepository: feeSetupRepo,
    feeMonthlyRepository: feeMonthlyRepo,
    feePaymentRepository: feePaymentRepo,
    feeBillingRepository: feeBillingRepo,
    feeCashbookRepository: feeCashbookRepo,
    schoolCashflowRepository: schoolCashflowRepo,
    operationsRepository: operationsRepo,
    examRepository: examRepo,
    attendanceRepository: attendanceRepo,
    staffStudentDirectoryRepository: staffStudentRepo,
    admissionRepository: admissionRepo,
    admissionDocumentService: documentService,
    admissionApprovalRepository: approvalRepo,
    ownerUserManagementRepository: ownerUsersRepo,
    schoolLogoService: logoService,
    principalAuthGateway: principalAuth,
    staffAuthGateway: staffAuth,
    staffPermissionGateway: staffPermissions,
    accountPasswordGateway: staffPasswordGateway,
  ));
}

/// The normal startup shows Login. startInPreview is for isolated widget tests.
class SupaModelSchoolApp extends StatefulWidget {
  const SupaModelSchoolApp({
    super.key,
    this.startInPreview = false,
    this.authGateway,
    this.academicRepository,
    this.dashboardRepository,
    this.principalDashboardRepository,
    this.studentDirectoryRepository,
    this.feeSetupRepository,
    this.feeMonthlyRepository,
    this.feePaymentRepository,
    this.feeBillingRepository,
    this.feeCashbookRepository,
    this.schoolCashflowRepository,
    this.operationsRepository,
    this.examRepository,
    this.attendanceRepository,
    this.staffStudentDirectoryRepository,
    this.admissionRepository,
    this.admissionDocumentService,
    this.admissionApprovalRepository,
    this.ownerUserManagementRepository,
    this.schoolLogoService,
    this.principalAuthGateway,
    this.staffAuthGateway,
    this.staffPermissionGateway,
    this.accountPasswordGateway,
  });
  final bool startInPreview;
  final OwnerAuthGateway? authGateway;
  final AcademicStructureRepository? academicRepository;
  final DashboardRepository? dashboardRepository;
  final DashboardRepository? principalDashboardRepository;
  final StudentDirectoryRepository? studentDirectoryRepository;
  final FeeSetupRepository? feeSetupRepository;
  final FeeMonthlyRepository? feeMonthlyRepository;
  final FeePaymentRepository? feePaymentRepository;
  final FeeBillingRepository? feeBillingRepository;
  final FeeCashbookRepository? feeCashbookRepository;
  final SchoolCashflowRepository? schoolCashflowRepository;
  final OwnerOperationsRepository? operationsRepository;
  final ExamRepository? examRepository;
  final AttendanceRepository? attendanceRepository;
  final StudentDirectoryRepository? staffStudentDirectoryRepository;
  final AdmissionDraftRepository? admissionRepository;
  final AdmissionDocumentService? admissionDocumentService;
  final AdmissionApprovalRepository? admissionApprovalRepository;
  final OwnerUserManagementRepository? ownerUserManagementRepository;
  final SchoolLogoService? schoolLogoService;
  final PrincipalAuthGateway? principalAuthGateway;
  final StaffAuthGateway? staffAuthGateway;
  final StaffPermissionGateway? staffPermissionGateway;
  final AccountPasswordGateway? accountPasswordGateway;

  @override
  State<SupaModelSchoolApp> createState() => _SupaModelSchoolAppState();
}

class _SupaModelSchoolAppState extends State<SupaModelSchoolApp> {
  ThemeMode themeMode = ThemeMode.system;
  bool? _preview;
  OwnerAccess? _authorized;
  PrincipalAccess? _principal;
  SchoolStaffAccess? _staff;
  bool _restoring = false;

  OwnerAuthGateway get _gateway =>
      widget.authGateway ?? const UnconfiguredOwnerAuthGateway();

  PrincipalAuthGateway get _principalGateway =>
      widget.principalAuthGateway ?? const UnconfiguredPrincipalAuthGateway();

  StaffAuthGateway get _staffGateway =>
      widget.staffAuthGateway ?? const UnconfiguredStaffAuthGateway();

  @override
  void initState() {
    super.initState();
    if ((_gateway.configured || _principalGateway.configured ||
         _staffGateway.configured) &&
        !widget.startInPreview) {
      _restoring = true;
      _restoreOwnerSession();
    }
  }

  Future<void> _restoreOwnerSession() async {
    // Check Principal before Owner. Owner.restore() signs out sessions
    // without an Owner role; it must not destroy an authorized Principal.
    PrincipalAccess? principal;
    OwnerAccess? authorized;
    SchoolStaffAccess? staff;
    try {
      principal = await _principalGateway.restore();
      if (principal == null) staff = await _staffGateway.restore();
      if (principal == null && staff == null) {
        authorized = await _gateway.restore();
      }
    } catch (_) {
      // Fail closed when no active verified membership exists.
    }
    if (!mounted) return;
    setState(() {
      _authorized = authorized;
      _principal = principal;
      _staff = staff;
      _restoring = false;
    });
  }

  Future<void> _signIn(String email, String password) async {
    OwnerAccess? authorized;
    PrincipalAccess? principal;
    SchoolStaffAccess? staff;
    try {
      authorized = await _gateway.signIn(email, password);
    } catch (error) {
      // Retry only after confirmed authentication with no Owner role,
      // never after bad credentials or a failed network request.
      if (!error.toString().contains('No unique authorized Owner membership')) {
        rethrow;
      }
      try {
        if (!_principalGateway.configured) throw StateError('No Principal gateway');
        principal = await _principalGateway.signIn(email, password);
      } catch (_) {
        if (!_staffGateway.configured) rethrow;
        staff = await _staffGateway.signIn(email, password);
      }
    }
    if (!mounted) return;
    setState(() {
      _authorized = authorized;
      _principal = principal;
      _staff = staff;
      _preview = false;
    });
  }

  Future<OwnerAccess> _saveInitialSetup(
      OwnerInitialSetupRequest request) async {
    final updated = await _gateway.completeInitialSetup(request);
    if (!mounted) return updated;
    setState(() => _authorized = updated);
    return updated;
  }

  Future<void> _exitShell() async {
    if (_principal != null) {
      await _principalGateway.signOut();
    } else if (_staff != null) {
      await _staffGateway.signOut();
    } else if (_authorized != null) {
      await _gateway.signOut();
    }
    if (!mounted) return;
    setState(() {
      _authorized = null;
      _principal = null;
      _staff = null;
      _preview = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview ?? widget.startInPreview;
    return MaterialApp(
      title: 'Supa Model School',
      debugShowCheckedModeBanner: false,
      theme: SchoolTheme.light(),
      darkTheme: SchoolTheme.dark(),
      themeMode: themeMode,
      home: _restoring
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _principal != null && widget.admissionApprovalRepository != null
              ? PrincipalAdmissionsHome(
                  key: ValueKey('principal-${_principal!.userId}'),
                  principal: _principal!,
                  repository: widget.admissionApprovalRepository!,
                  dashboardRepository: widget.principalDashboardRepository,
                  logoService: widget.schoolLogoService,
                  permissionGateway: widget.staffPermissionGateway,
                  studentRepository: widget.staffStudentDirectoryRepository,
                  examRepository: widget.examRepository,
                  feePaymentRepository: widget.feePaymentRepository,
                  feeBillingRepository: widget.feeBillingRepository,
                  feeCashbookRepository: widget.feeCashbookRepository,
                  onSignOut: _exitShell,
                  passwordGateway: widget.accountPasswordGateway,
                )
              : _staff != null && widget.accountPasswordGateway != null
              ? StaffAccountHome(
                  key: ValueKey('staff-${_staff!.userId}'),
                  staff: _staff!,
                  permissionGateway: widget.staffPermissionGateway,
                  studentRepository: widget.staffStudentDirectoryRepository,
                  examRepository: widget.examRepository,
                  attendanceRepository: widget.attendanceRepository,
                  feePaymentRepository: widget.feePaymentRepository,
                  feeBillingRepository: widget.feeBillingRepository,
                  feeCashbookRepository: widget.feeCashbookRepository,
                  passwordGateway: widget.accountPasswordGateway!,
                  onSignOut: _exitShell,
                )
              : (_authorized != null || preview)
              ? _SchoolShell(
                  key: ValueKey(_authorized?.userId ?? 'debug-preview'),
                  owner: _authorized,
                  academicRepository: widget.academicRepository ??
                      const UnconfiguredAcademicStructureRepository(),
                  dashboardRepository: widget.dashboardRepository ??
                      const UnconfiguredDashboardRepository(),
                  studentDirectoryRepository: widget.studentDirectoryRepository,
                  feeSetupRepository: widget.feeSetupRepository,
                  feeMonthlyRepository: widget.feeMonthlyRepository,
                  feePaymentRepository: widget.feePaymentRepository,
                  feeBillingRepository: widget.feeBillingRepository,
                  feeCashbookRepository: widget.feeCashbookRepository,
                  schoolCashflowRepository: widget.schoolCashflowRepository,
                  operationsRepository: widget.operationsRepository,
                  examRepository: widget.examRepository,
                  attendanceRepository: widget.attendanceRepository,
                  admissionRepository: widget.admissionRepository,
                  admissionDocumentService: widget.admissionDocumentService,
                  admissionApprovalRepository: widget.admissionApprovalRepository,
                  ownerUserManagementRepository: widget.ownerUserManagementRepository,
                   schoolLogoService: widget.schoolLogoService,
                   themeMode: themeMode,
                  onThemeChanged: (mode) => setState(() => themeMode = mode),
                  onExit: _exitShell,
                  onChangePassword: _gateway.changePassword,
                  onSaveSetup: _saveInitialSetup,
                  onPasswordChanged: () => setState(() {
                    _authorized = null;
                    _preview = false;
                  }),
                )
              : LoginPage(
                  themeMode: themeMode,
                  authConfigured: _gateway.configured,
                  onSignIn: _signIn,
                  onRecoverPassword: _gateway.sendRecovery,
                  onThemeChanged: (mode) => setState(() => themeMode = mode),
                  onOpenDemo: () => setState(() => _preview = true),
                ),
    );
  }
}

class _SchoolShell extends StatefulWidget {
  const _SchoolShell({
    super.key,
    required this.themeMode,
    required this.onThemeChanged,
    required this.onExit,
    required this.onChangePassword,
    required this.onSaveSetup,
    required this.onPasswordChanged,
    required this.academicRepository,
    required this.dashboardRepository,
    this.studentDirectoryRepository,
    this.feeSetupRepository,
    this.feeMonthlyRepository,
    this.feePaymentRepository,
    this.feeBillingRepository,
    this.feeCashbookRepository,
    this.schoolCashflowRepository,
    this.operationsRepository,
    this.examRepository,
    this.attendanceRepository,
    this.admissionRepository,
    this.admissionDocumentService,
    this.admissionApprovalRepository,
    this.ownerUserManagementRepository,
    this.schoolLogoService,
    this.owner,
  });
  final OwnerAccess? owner;
  final AcademicStructureRepository academicRepository;
  final DashboardRepository dashboardRepository;
  final StudentDirectoryRepository? studentDirectoryRepository;
  final FeeSetupRepository? feeSetupRepository;
  final FeeMonthlyRepository? feeMonthlyRepository;
  final FeePaymentRepository? feePaymentRepository;
  final FeeBillingRepository? feeBillingRepository;
  final FeeCashbookRepository? feeCashbookRepository;
  final SchoolCashflowRepository? schoolCashflowRepository;
  final OwnerOperationsRepository? operationsRepository;
  final ExamRepository? examRepository;
  final AttendanceRepository? attendanceRepository;
  final AdmissionDraftRepository? admissionRepository;
  final AdmissionDocumentService? admissionDocumentService;
  final AdmissionApprovalRepository? admissionApprovalRepository;
  final OwnerUserManagementRepository? ownerUserManagementRepository;
  final SchoolLogoService? schoolLogoService;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback onExit;
  final Future<void> Function(String, String) onChangePassword;
  final Future<OwnerAccess> Function(OwnerInitialSetupRequest) onSaveSetup;
  final VoidCallback onPasswordChanged;

  @override
  State<_SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends State<_SchoolShell> {
  int selected = 0;
  String? activeCampusId;
  int _admissionListRevision = 0;

  @override
  void initState() {
    super.initState();
    // The first verified Owner lands in setup until the real configuration
    // is saved. The debug dashboard preview remains separate.
    if (widget.owner != null && !widget.owner!.setupComplete) {
       selected = 10; // Owner Control Panel / Settings.
    }
    if (widget.owner != null) {
      widget.schoolLogoService?.load(widget.owner!.logoStoragePath);
    }
  }

  static const modules = <String>[
    'Dashboard', 'Students', 'Admissions', 'Fees', 'Attendance',
    'Employees', 'Payroll', 'Expenses', 'Reports', 'Sync Center', 'Settings',
    'Academic Setup', 'Transport', 'Examinations',
  ];

  static const icons = <IconData>[
    Icons.dashboard_outlined,
    Icons.groups_outlined,
    Icons.school_outlined,
    Icons.paid_outlined,
    Icons.calendar_month_outlined,
    Icons.badge_outlined,
    Icons.account_balance_wallet_outlined,
    Icons.receipt_long_outlined,
    Icons.bar_chart_outlined,
    Icons.sync,
    Icons.settings_outlined,
    Icons.school_outlined,
    Icons.directions_bus_outlined,
    Icons.fact_check_outlined,
  ];

  Future<void> _newAdmission() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => AdmissionWizardPage(
        // Only a verified Owner receives real academic options. The
        // unauthenticated debug preview intentionally has no sample IDs.
        owner: widget.owner,
        academicRepository:
            widget.owner == null ? null : widget.academicRepository,
        admissionRepository:
            widget.owner == null ? null : widget.admissionRepository,
        documentService:
            widget.owner == null ? null : widget.admissionDocumentService,
        approvalRepository:
             widget.owner == null ? null : widget.admissionApprovalRepository,
         logoService: widget.schoolLogoService,
         selectedCampusId: activeCampusId,
        onOpenSearch: _showGlobalSearch,
        onCampusChanged: (campusId) =>
            setState(() => activeCampusId = campusId),
        onNavigateModule: (index) => setState(() => selected = index),
      ),
    ));
    if (mounted) setState(() => _admissionListRevision++);
  }

  Future<void> _resumeAdmission(AdmissionDraftRecord record) async {
    final owner = widget.owner;
    if (owner == null ||
        record.academicYearId != owner.activeYearId ||
        !owner.campuses.any((campus) => campus.id == record.campusId)) {
      return;
    }
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => AdmissionWizardPage(
        owner: owner,
        academicRepository: widget.academicRepository,
        admissionRepository: widget.admissionRepository,
        documentService: widget.admissionDocumentService,
        approvalRepository: widget.admissionApprovalRepository,
         logoService: widget.schoolLogoService,
         selectedCampusId: record.campusId,
        initialRecord: record,
        onOpenSearch: _showGlobalSearch,
        onCampusChanged: (campusId) =>
            setState(() => activeCampusId = campusId),
        onNavigateModule: (index) => setState(() => selected = index),
      ),
    ));
    if (mounted) setState(() => _admissionListRevision++);
  }

  void _showGlobalSearch() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Global Search'),
        content: const SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: Key('global-search-input'),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Students, employees, invoices...',
              ),
            ),
            SizedBox(height: 12),
            Text('Preview only. Authorized server-side searching '
                'will be added after RLS and domain modules are tested.'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _modulePreview() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icons[selected], size: 48,
            color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(modules[selected],
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 10),
        const Text(
          'Module preview only. No authenticated cloud operations, '
          'financial posting, attendance entry or offline sync '
          'are implemented on this screen.',
          textAlign: TextAlign.center,
        ),
        if (selected == 2) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _newAdmission,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('New Admission (preview)'),
          ),
        ],
      ]),
    ),
  );

  Widget _content() {
    if (selected == 0) {
      return DashboardPage(
        onNewAdmission: _newAdmission,
        onStudents: () => setState(() => selected = 1),
        onFees: () => setState(() => selected = 3),
        onAttendance: () => setState(() => selected = 4),
        onExpenses: () => setState(() => selected = 7),
        onAdmissions: () => setState(() => selected = 2),
        onSearch: _showGlobalSearch,
        onExit: widget.onExit,
        owner: widget.owner,
        selectedCampusId: activeCampusId,
        onCampusChanged: (campusId) =>
            setState(() => activeCampusId = campusId),
        repository: widget.dashboardRepository,
         logoService: widget.schoolLogoService,
       );
    }
    if (selected == 2 && widget.owner != null &&
        widget.admissionRepository != null) {
      return AdmissionDraftListPage(
        key: ValueKey('admissions-$_admissionListRevision-$activeCampusId'),
        owner: widget.owner!,
        repository: widget.admissionRepository!,
        selectedCampusId: activeCampusId,
        onNewAdmission: _newAdmission,
        onOpenDraft: _resumeAdmission,
      );
    }
    if (selected == 1) {
      return StudentDirectoryPage(
        onNewAdmission: _newAdmission,
        owner: widget.owner,
        selectedCampusId: activeCampusId,
        repository: widget.studentDirectoryRepository,
      );
    }
    if (selected == 3 && widget.owner != null &&
        widget.feeSetupRepository != null &&
        widget.feeMonthlyRepository != null) {
      return FeeFinancePage(
        key: ValueKey('fee-finance-$activeCampusId'),
        owner: widget.owner!,
        setupRepository: widget.feeSetupRepository!,
        monthlyRepository: widget.feeMonthlyRepository!,
        paymentRepository: widget.feePaymentRepository,
        billingRepository: widget.feeBillingRepository,
        cashbookRepository: widget.feeCashbookRepository,
        schoolCashflowRepository: widget.schoolCashflowRepository,
        selectedCampusId: activeCampusId,
      );
    }
    if (selected == 4 && widget.owner != null &&
        widget.attendanceRepository != null) {
      return OwnerAttendanceSetupPage(
        key: ValueKey('owner-attendance-$activeCampusId'),
        owner: widget.owner!,
        repository: widget.attendanceRepository!,
        selectedCampusId: activeCampusId,
      );
    }
    if (selected == 5 && widget.owner != null &&
        widget.operationsRepository != null) {
      return OwnerStaffDirectoryPage(
        key: ValueKey('owner-staff-$activeCampusId'),
        owner: widget.owner!,
        repository: widget.operationsRepository!,
        selectedCampusId: activeCampusId,
      );
    }
    if (selected == 12 && widget.owner != null &&
        widget.operationsRepository != null) {
      return OwnerTransportDirectoryPage(
        key: ValueKey('owner-transport-$activeCampusId'),
        owner: widget.owner!,
        repository: widget.operationsRepository!,
        selectedCampusId: activeCampusId,
      );
    }
    if (selected == 13 && widget.owner != null && widget.examRepository != null) {
      return ExamManagementPage(
        key: ValueKey('owner-exams-$activeCampusId'),
        repository: widget.examRepository!,
        schoolId: widget.owner!.schoolId,
        campusId: activeCampusId ?? widget.owner!.campuses.first.id,
        yearId: widget.owner!.activeYearId,
      );
    }
    if (selected == 10 && widget.owner != null) {
      return OwnerControlPanelPage(
        owner: widget.owner!,
        onChangePassword: widget.onChangePassword,
        onPasswordChanged: widget.onPasswordChanged,
        onSaveSetup: widget.onSaveSetup,
        onSetupSaved: (updated) {
          setState(() => activeCampusId = updated.campuses.first.id);
        },
        onOpenAcademicStructure: () => setState(() => selected = 11),
        userManagementRepository: widget.ownerUserManagementRepository,
         logoService: widget.schoolLogoService,
       );
    }
    if (selected == 11 && widget.owner != null) {
      return AcademicStructurePage(
        owner: widget.owner!,
        repository: widget.academicRepository,
      );
    }
    return _modulePreview();
  }

  Widget _themeMenu() => PopupMenuButton<ThemeMode>(
    tooltip: 'Change appearance',
    icon: const Icon(Icons.contrast_outlined),
    onSelected: widget.onThemeChanged,
    itemBuilder: (_) => const [
      PopupMenuItem(value: ThemeMode.system, child: Text('System')),
      PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
      PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
    ],
  );

  Widget _settingsAppearance() => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        const Icon(Icons.contrast_outlined),
        const SizedBox(width: 12),
        const Expanded(child: Text('Appearance — System, Light or Dark')),
        _themeMenu(),
      ]),
    ),
  );

  void _openMore() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < modules.length; i++)
              ListTile(
                leading: Icon(icons[i]),
                title: Text(modules[i]),
                onTap: () {
                  setState(() => selected = i);
                  Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _desktopSidebar(bool extended) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = Theme.of(context).colorScheme.onSurface;
    return Container(
      key: const Key('desktop-navigation'),
      width: extended ? 248 : 68,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(right: BorderSide(color: Color(0xFFDDE8ED))),
      ),
      child: Stack(children: [
        if (selected == 0 && !dark)
          const Positioned(
            left: 0, right: 0, bottom: 0, height: 150,
            child: DashboardWaveBackground(),
          ),
        Column(children: [
          if (extended)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 13, 9, 13),
              child: Column(children: [
                const SchoolMark(size: 77),
                const SizedBox(height: 3),
                Text('Supa Model School',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: -.5,
                  )),
                const SizedBox(height: 3),
                Text('School Management System',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ink, fontSize: 11)),
                const SizedBox(height: 10),
                const Divider(height: 1, indent: 11, endIndent: 11,
                  color: Color(0xFFD3E2E9)),
              ]),
            )
          else
            const SizedBox(height: 18),
          Expanded(child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            children: [
              for (var i = 0; i < modules.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: selected == i
                            ? const LinearGradient(
                                colors: [Color(0xFF079989), Color(0xFF005651)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: InkWell(
                        key: Key('dashboard-nav-$i'),
                        onTap: () => setState(() => selected = i),
                        borderRadius: BorderRadius.circular(9),
                        child: SizedBox(height: 39, child: Row(children: [
                          const SizedBox(width: 12),
                          Icon(i == 0 && selected == i
                                  ? Icons.home_rounded : icons[i],
                            size: 21,
                            color: selected == i ? Colors.white : ink),
                          if (extended) ...[
                            const SizedBox(width: 13),
                            Expanded(child: Text(modules[i],
                              style: TextStyle(
                                color: selected == i ? Colors.white : ink,
                                fontSize: 13,
                                fontWeight: selected == i
                                    ? FontWeight.w800 : FontWeight.w500,
                              ),
                            )),
                          ],
                        ])),
                      ),
                    ),
                  ),
                ),
            ],
          )),
        ]),
      ]),
    );
  }

  Widget _dashboardFooter() => Container(
    key: const Key('dashboard-desktop-footer'),
    height: 43,
    padding: const EdgeInsets.symmetric(horizontal: 24),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF007B72), Color(0xFF004B48)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
    child: const Row(children: [
      Icon(Icons.verified_user_outlined, size: 20, color: Colors.white),
      SizedBox(width: 8),
      Expanded(child: Text(
        'Secure access for authorized staff only',
        style: TextStyle(color: Colors.white, fontSize: 12),
      )),
      Text('│', style: TextStyle(color: Color(0xFF8AC7C5))),
      SizedBox(width: 11),
      Text('Supa Model School v1.0.0',
        style: TextStyle(color: Colors.white, fontSize: 12)),
    ]),
  );

  void _dashboardNavigate(int destination) {
    switch (destination) {
      case 0:
        setState(() => selected = 0);
      case 1:
        setState(() => selected = 1);
      case 2:
        setState(() => selected = 3);
      case 3:
        setState(() => selected = 4);
      default:
        _openMore();
    }
  }

  Widget _dashboardMobileNavigation() {
    const items = <(String, IconData)>[
      ('Home', Icons.home_rounded),
      ('Students', Icons.groups_outlined),
      ('Fees', Icons.savings_outlined),
      ('Attendance', Icons.event_available_outlined),
      ('More', Icons.grid_view_rounded),
    ];
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('mobile-navigation'),
        height: 66,
         padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFD7E3E8))),
        ),
        child: Row(children: [
          for (var i = 0; i < items.length; i++)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    gradient: i == 0
                        ? const LinearGradient(
                            colors: [Color(0xFF008D7E), Color(0xFF00534F)])
                        : null,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: InkWell(
                    onTap: () => _dashboardNavigate(i),
                    borderRadius: BorderRadius.circular(15),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(items[i].$2,
                          color: i == 0
                              ? Colors.white : const Color(0xFF53626D),
                          size: 24),
                        const SizedBox(height: 3),
                        Text(items[i].$1,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == 0
                                ? Colors.white : const Color(0xFF53626D),
                            fontSize: 11,
                            fontWeight: i == 0
                                ? FontWeight.w800 : FontWeight.w500,
                          )),
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

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 860;
    final extended = MediaQuery.sizeOf(context).width >= 1190;
    final content = _content();
    final owner = widget.owner;
    final activeCampus = owner == null ? null : owner.campuses.firstWhere(
      (campus) => campus.id == activeCampusId,
      orElse: () => owner.campuses.first,
    );
    final mobileIndex = switch (selected) {
      0 => 0,
      1 => 1,
      3 => 2,
      4 => 3,
      _ => 4,
    };

    return Scaffold(
      // The shell keeps one permanent sidebar. Changing modules replaces
      // only the right-hand content pane; no shared header/AppBar is added.
      appBar: null,
      body: SafeArea(
        top: !desktop,
        bottom: false,
        child: desktop
          ? Row(children: [
              _desktopSidebar(extended),
              const VerticalDivider(width: 1),
              Expanded(child: Column(children: [
                if (selected == 10) _settingsAppearance(),
                Expanded(child: content),
              ])),
            ])
          : Column(children: [
              if (selected == 10) _settingsAppearance(),
              Expanded(child: content),
             ])),
      bottomNavigationBar: desktop
          ? (selected == 0 ? _dashboardFooter() : null)
          : selected == 0
              ? _dashboardMobileNavigation()
              : NavigationBar(
        key: const Key('mobile-navigation'),
        selectedIndex: mobileIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              setState(() => selected = 0);
            case 1:
              setState(() => selected = 1);
            case 2:
              setState(() => selected = 3);
            case 3:
              setState(() => selected = 4);
            default:
              _openMore();
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.groups_outlined),
              label: 'Students'),
          NavigationDestination(icon: Icon(Icons.paid_outlined), label: 'Fees'),
          NavigationDestination(icon: Icon(Icons.event_available_outlined),
              label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined),
              label: 'More'),
        ],
      ),
    );
  }
}
