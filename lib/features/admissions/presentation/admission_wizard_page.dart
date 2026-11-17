import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'dart:math';
import '../data/admission_draft_repository.dart';

import '../../academics/data/academic_structure_repository.dart';
import '../../auth/data/owner_auth_gateway.dart';
import '../models/admission_draft.dart';
import '../../../ui/school_brand.dart';

/// First-stage admissions UI for Windows and Android.
///
/// Only the academic selectors can load read-only, authorized DB01 records.
/// The applicant form remains strictly in memory: no DB02 admission/identity
/// writes, private document uploads, offline queue, or payment operations.
class AdmissionWizardPage extends StatefulWidget {
  const AdmissionWizardPage({
    super.key,
    this.owner,
    this.academicRepository,
    this.admissionRepository,
    this.initialStep = AdmissionStep.student,
    this.selectedCampusId,
    this.onOpenSearch,
    this.onCampusChanged,
    this.onNavigateModule,
  });

  /// Widget-test seam; production navigation always starts at Student.
  @visibleForTesting
  final AdmissionStep initialStep;

  /// Null means design preview; never substitute fictional academic IDs.
  final OwnerAccess? owner;
  final AcademicStructureRepository? academicRepository;
  final AdmissionDraftRepository? admissionRepository;
  final String? selectedCampusId;
  final VoidCallback? onOpenSearch;
  final ValueChanged<String>? onCampusChanged;
  final ValueChanged<int>? onNavigateModule;

  @override
  State<AdmissionWizardPage> createState() => _AdmissionWizardPageState();
}

class _AdmissionWizardPageState extends State<AdmissionWizardPage> {
  final AdmissionDraft _draft = AdmissionDraft();
  late int _step;
  int _nextGuardianId = 2;
  String? _error;
  bool _allowExit = false;
  List<SchoolClassRecord> _academicClasses = [];
  bool _academicLoading = false;
  String? _academicError;
  int _academicLoadVersion = 0;
  SavedAdmissionDraft? _savedDraft;
  AdmissionDraftSaveRequest? _pendingSave;
  bool _savingDraft = false;

  bool get _canSaveDraft =>
      !_savingDraft && widget.owner?.setupComplete == true &&
      widget.admissionRepository != null;

  String _operationUuid() {
    final rng = Random.secure();
    final b = List<int>.generate(16, (_) => rng.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0,8)}-${h.substring(8,12)}-'
        '${h.substring(12,16)}-${h.substring(16,20)}-${h.substring(20)}';
  }

  Future<void> _saveDraft() async {
    if (!_canSaveDraft) return;
    final owner = widget.owner!;
    if (_pendingSave == null) {
      if (_draft.studentName.trim().length < 2 ||
          _draft.campusId == null ||
          _draft.academicYearId != owner.activeYearId ||
          !owner.campuses.any((c) => c.id == _draft.campusId) ||
          (_draft.classId != null && !_classChoices.containsKey(_draft.classId)) ||
          (_draft.sectionId != null && !_sectionChoices.containsKey(_draft.sectionId))) {
        setState(() => _error =
            'Enter a student name and choose a valid campus, year and class.');
        return;
      }
      final guardians = <Map<String, dynamic>>[
        for (final guardian in _draft.guardians)
          if (guardian.fullName.trim().isNotEmpty)
            {
              'full_name': guardian.fullName.trim(),
              'relationship': guardian.relationship,
              'phone': guardian.phone.trim(),
              'is_primary': guardian.isPrimary,
              'is_legal_guardian': guardian.isLegalGuardian,
            }
      ];
      if (guardians.length > 8 ||
          guardians.where((g) => g['is_primary'] == true).length > 1) {
        setState(() => _error = 'Review guardian details before saving.');
        return;
      }
      _pendingSave = AdmissionDraftSaveRequest(
        schoolId: owner.schoolId,
        campusId: _draft.campusId!,
        academicYearId: _draft.academicYearId!,
        operationId: _operationUuid(),
        applicantName: _draft.studentName.trim(),
        dateOfBirth: _draft.dateOfBirth,
        previousSchool: _draft.previousSchool,
        classId: _draft.classId,
        sectionId: _draft.sectionId,
        guardians: guardians,
        applicationId: _savedDraft?.id,
        expectedRevision: _savedDraft?.revision,
      );
    }
    // Network-uncertain retries use the SAME immutable request and UUID.
    setState(() { _savingDraft = true; _error = null; });
    try {
      final result = await widget.admissionRepository!.saveDraft(_pendingSave!);
      if (!mounted) return;
      setState(() {
        _savedDraft = result;
        _pendingSave = null;
        _savingDraft = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Draft saved in Supabase (revision ${result.revision}). '
            'Not submitted or approved.'),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingDraft = false;
        _error = 'Save not confirmed. Retry to repeat the same operation '
            'without creating a duplicate draft.';
      });
    }
  }


  bool get _academicReady =>
      widget.owner?.setupComplete == true &&
      widget.owner?.activeYearId != null &&
      widget.owner?.campuses.isNotEmpty == true &&
      widget.academicRepository != null;

  Map<String, String> get _campusChoices => {
        if (_academicReady)
          for (final campus in widget.owner!.campuses)
            campus.id: campus.name,
      };

  Map<String, String> get _yearChoices => {
        if (_academicReady)
          widget.owner!.activeYearId!: widget.owner!.activeYearLabel ??
              'Current academic year',
      };

  Map<String, String> get _classChoices => {
        for (final schoolClass in _academicClasses)
          schoolClass.id: schoolClass.name,
      };

  Map<String, String> get _sectionChoices {
    for (final schoolClass in _academicClasses) {
      if (schoolClass.id == _draft.classId) {
        return {
          for (final section in schoolClass.sections)
            section.id: section.name,
        };
      }
    }
    return {};
  }

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep.index;
    // The active year ID is verified from DB01. The user chooses a campus,
    // and only its scoped class/section records will then be queried.
    if (_academicReady) {
      _draft.academicYearId = widget.owner!.activeYearId;
      if (widget.selectedCampusId != null &&
          _campusChoices.containsKey(widget.selectedCampusId)) {
        _draft.campusId = widget.selectedCampusId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadClasses(widget.selectedCampusId!);
        });
      }
    }
  }

  void _chooseCampus(String? id) {
    if (!_academicReady || (id != null && !_campusChoices.containsKey(id))) {
      return;
    }
    ++_academicLoadVersion; // Invalidate any previous network reply.
    setState(() {
      _draft.campusId = id;
      _draft.academicYearId = widget.owner!.activeYearId;
      _draft.classId = null;
      _draft.sectionId = null;
      _academicClasses = [];
      _academicLoading = false;
      _academicError = null;
      _error = null;
    });
    if (id != null) {
      widget.onCampusChanged?.call(id);
      _loadClasses(id);
    }
  }

  Future<void> _loadClasses(String campusId) async {
    if (!_academicReady || !_campusChoices.containsKey(campusId)) return;
    final version = ++_academicLoadVersion;
    setState(() {
      _academicLoading = true;
      _academicError = null;
    });
    try {
      final rows = await widget.academicRepository!.listClasses(
        campusId: campusId,
        academicYearId: widget.owner!.activeYearId!,
      );
      if (!mounted || version != _academicLoadVersion ||
          _draft.campusId != campusId) return;
      setState(() {
        _academicClasses = rows;
        _academicLoading = false;
      });
    } catch (_) {
      if (!mounted || version != _academicLoadVersion) return;
      setState(() {
        _academicClasses = [];
        _draft.classId = null;
        _draft.sectionId = null;
        _academicLoading = false;
        _academicError =
            'Class options could not be loaded. Check your network and '
            'Owner campus permissions, then retry.';
      });
    }
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Select date';
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  Future<void> _chooseBirthDate() async {
    final today = DateTime.now();
    final chosen = await showDatePicker(
      context: context,
      initialDate: _draft.dateOfBirth ?? DateTime(2015, 1, 1),
      firstDate: DateTime(1980),
      lastDate: today,
      helpText: 'Student date of birth',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _draft.dateOfBirth = chosen;
      _error = null;
    });
  }

  Future<void> _chooseDocumentDeadline() async {
    final today = DateTime.now();
    final currentDay = DateTime(today.year, today.month, today.day);
    final chosen = await showDatePicker(
      context: context,
      initialDate: _draft.missingDocumentsDueOn ??
          AdmissionDraft.latestConditionalDeadline(currentDay),
      firstDate: currentDay,
      // Match deployed DB02 conditional admission rule, including month end.
      lastDate: AdmissionDraft.latestConditionalDeadline(currentDay),
      helpText: 'Deadline for outstanding certificates',
    );
    if (!mounted || chosen == null) return;
    setState(() {
      _draft.missingDocumentsDueOn = chosen;
      _error = null;
    });
  }

  void _next() {
    if (AdmissionStep.values[_step] == AdmissionStep.academic) {
      if (!_academicReady) {
        setState(() => _error =
            'Complete Owner school setup and academic structure first.');
        return;
      }
      if (_academicLoading || _academicError != null ||
          !_campusChoices.containsKey(_draft.campusId) ||
          _draft.academicYearId != widget.owner!.activeYearId ||
          !_classChoices.containsKey(_draft.classId)) {
        setState(() => _error =
            'Select an authorized campus and a loaded class in the active '
            'academic year before continuing.');
        return;
      }
      if (_draft.sectionId != null &&
          !_sectionChoices.containsKey(_draft.sectionId)) {
        setState(() => _error =
            'The selected section is no longer available.');
        return;
      }
    }
    final error = _draft.validateStep(AdmissionStep.values[_step]);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (_step < AdmissionStep.values.length - 1) {
      setState(() {
        _step += 1;
        _error = null;
      });
    }
  }

  void _previous() {
    if (_step == 0) return;
    setState(() {
      _step -= 1;
      _error = null;
    });
  }

  Future<void> _confirmExit({VoidCallback? onExited}) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_savedDraft == null ? 'Discard admission preview?' : 'Leave saved draft?'),
        content: Text(
          _savedDraft == null
            ? 'Unsaved admission details will be lost when you leave.'
            : 'The last confirmed draft is saved in Supabase. Unsaved changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Continue editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_savedDraft == null ? 'Discard preview' : 'Leave draft'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    setState(() => _allowExit = true);
    // PopScope must rebuild with canPop=true before popping the route.
    // Otherwise a second interception can reopen the confirmation dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      onExited?.call();
    });
  }


  // Route all navigation through the existing admission exit confirmation.
  // No separate shell is created; the original draft is discarded explicitly.
  void _openModule(int index) {
    if (widget.onNavigateModule == null) {
      _confirmExit();
      return;
    }
    _confirmExit(onExited: () => widget.onNavigateModule?.call(index));
  }

  void _openSearch() {
    final callback = widget.onOpenSearch;
    if (callback != null) {
      callback();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Global search is not configured in this preview.'),
      ));
    }
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Notifications are not connected to live data yet.'),
    ));
  }

  // Follow the parent MaterialApp ThemeMode, configured in Settings.
  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _teal => _dark ? Color(0xFF6BDBD0) : Color(0xFF00635D);
  Color get _pale => _dark ? Color(0xFF193B3D) : Color(0xFFE7F5F6);
  Color get _ink => _dark ? Color(0xFFF0F8FC) : Color(0xFF193745);
  Color get _line => _dark ? Color(0xFF35515C) : Color(0xFFD5E2E8);
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _subSurface => _dark ? Color(0xFF203740) : Color(0xFFF8FCFF);
  Color get _fieldSurface => _dark ? Color(0xFF20333C) : Colors.white;
  Color get _muted => _dark ? Color(0xFFBDD2DC) : Color(0xFF5A7382);
  Color get _warningSurface => _dark ? Color(0xFF413621) : Color(0xFFFFF4DC);

  IconData _stepIcon(AdmissionStep step) => switch (step) {
    AdmissionStep.student => Icons.person_outline_rounded,
    AdmissionStep.guardians => Icons.groups_outlined,
    AdmissionStep.academic => Icons.school_outlined,
    AdmissionStep.documents => Icons.description_outlined,
    AdmissionStep.fees => Icons.savings_outlined,
    AdmissionStep.review => Icons.check_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1250;
    return Theme(
      data: Theme.of(context).copyWith(
        // Never create a second light-only color scheme for this route.
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: _fieldSurface,
          contentPadding: EdgeInsets.symmetric(
              horizontal: 13, vertical: 12),
          border: OutlineInputBorder(
            borderSide: BorderSide(color: _line),
            borderRadius: BorderRadius.circular(7)),
        ),
      ),
      child: PopScope(
        canPop: _allowExit,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          key: Key('admission-wizard-screen'),
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: wide ? _desktopLayout() : _mobileLayout(),
          ),
          bottomNavigationBar: wide ? _footerBar() : null,
        ),
      ),
    );
  }

  Widget _brandRow({bool mobile = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SchoolMark(size: mobile ? 57 : 65),
      SizedBox(width: 11),
      Flexible(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Supa Model School',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _teal, fontWeight: FontWeight.w900,
              fontSize: mobile ? 20 : 19)),
          Text('School Management System',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink, fontSize: mobile ? 12 : 11)),
        ],
      )),
    ],
  );

  // The native Windows titlebar already displays the brand. Do not
  // introduce a second dark green strip below it.
  Widget _desktopLayout() => Row(children: [
    _sidebar(),
    Expanded(child: Column(children: [
      _desktopToolbar(),
      Expanded(child: _admissionScroll(wide: true)),
    ])),
  ]);

  Widget _sidebar() {
    const names = <String>['Dashboard', 'Students', 'Admissions', 'Fees',
      'Attendance', 'Employees', 'Payroll', 'Expenses', 'Reports',
      'Sync Center', 'Settings', 'Academic Setup'];
    const icons = <IconData>[Icons.home_outlined, Icons.groups_outlined,
      Icons.school_outlined, Icons.savings_outlined,
      Icons.calendar_month_outlined, Icons.people_outline,
      Icons.account_balance_wallet_outlined, Icons.receipt_long_outlined,
      Icons.bar_chart_outlined, Icons.sync_outlined,
      Icons.settings_outlined, Icons.school_outlined];
    return Container(
      key: Key('admission-desktop-sidebar'),
      width: 248,
      decoration: BoxDecoration(
        color: _surface,
        border: Border(right: BorderSide(color: _line))),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(12, 13, 12, 17),
          child: Column(children: [
            SchoolMark(size: 77),
            SizedBox(height: 5),
            Text('Supa Model School',
              style: TextStyle(color: _teal, fontWeight: FontWeight.w900,
                fontSize: 18)),
            Text('School Management System',
              style: TextStyle(fontSize: 11, color: _ink)),
            Divider(height: 24, color: _line),
          ]),
        ),
        Expanded(child: ListView(
          padding: EdgeInsets.symmetric(horizontal: 11),
          children: [
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: 3),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: Key('admission-nav-$i'),
                    onTap: i == 2 ? null : () => _openModule(i),
                    borderRadius: BorderRadius.circular(9),
                    child: Ink(
                      height: 39,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        gradient: i == 2
                            ? LinearGradient(colors: [
                                Color(0xFF079989), Color(0xFF005651)])
                            : null),
                      child: Row(children: [
                        SizedBox(width: 12),
                        Icon(icons[i], size: 21,
                          color: i == 2 ? Colors.white : _ink),
                        SizedBox(width: 13),
                        Expanded(child: Text(names[i],
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == 2 ? Colors.white : _ink,
                            fontWeight: i == 2
                                ? FontWeight.w800 : FontWeight.w500,
                            fontSize: 13))),
                      ]),
                    ),
                  ),
                ),
              ),
          ],
        )),
      ]),
    );
  }

  // Dimensions and search styling match the dashboard toolbar.
  Widget _desktopToolbar() => Container(
    height: 73,
    padding: EdgeInsets.symmetric(horizontal: 22),
    child: Row(children: [
      Expanded(flex: 4, child: SizedBox(
        height: 46,
        child: OutlinedButton(
          key: Key('admission-global-search'),
          onPressed: _openSearch,
          style: OutlinedButton.styleFrom(
            backgroundColor: _surface,
            foregroundColor: _ink,
            padding: EdgeInsets.symmetric(horizontal: 13),
            side: BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11))),
          child: Row(children: [
            Icon(Icons.search, size: 24),
            SizedBox(width: 12),
            Expanded(child: Text('Search students, staff, invoices, etc...',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13))),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: _pale,
                borderRadius: BorderRadius.circular(12)),
              child: Text('Ctrl + K',
                style: TextStyle(color: _ink, fontSize: 11)),
            ),
          ]),
        ),
      )),
      SizedBox(width: 20),
      Container(width: 1, height: 32, color: _line),
      SizedBox(width: 20),
      PopupMenuButton<String>(
        key: Key('admission-campus-selector'),
        tooltip: 'Authorized campus',
        enabled: (widget.owner?.campuses.length ?? 0) > 1,
        onSelected: _chooseCampus,
        itemBuilder: (_) => [
          for (final campus in widget.owner?.campuses ?? <OwnerCampus>[])
            PopupMenuItem(value: campus.id, child: Text(campus.name)),
        ],
        child: _topPill(Icons.location_city_outlined,
          widget.owner?.campuses.isNotEmpty == true
            ? widget.owner!.campuses.firstWhere(
                (c) => c.id == _draft.campusId,
                orElse: () => widget.owner!.campuses.first).name
            : 'School / Campus'),
      ),
      SizedBox(width: 12),
      _topPill(Icons.calendar_month_outlined,
        widget.owner?.activeYearLabel ?? 'Academic Year'),
      SizedBox(width: 12),
      IconButton(
        tooltip: 'Notifications (preview)',
        onPressed: _showNotifications,
        icon: Icon(Icons.notifications_none_rounded, color: _teal, size: 25)),
      SizedBox(width: 10),
      PopupMenuButton<String>(
        tooltip: 'Account',
        onSelected: (option) {
          if (option == 'exit') _confirmExit();
          if (option == 'settings') _openModule(10);
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'settings', child: Text('Settings')),
          PopupMenuItem(value: 'exit', child: Text('Back to school')),
        ],
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(radius: 19, backgroundColor: _pale,
            child: Icon(Icons.person_outline, color: _teal)),
          SizedBox(width: 7),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 115),
            child: Text(widget.owner?.displayName ?? 'Demo Administrator',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12,
                color: _ink, fontWeight: FontWeight.w700))),
          Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: _ink),
        ]),
      ),
    ]),
  );

  Widget _topPill(IconData icon, String label) => Container(
    height: 43,
    constraints: BoxConstraints(maxWidth: 215),
    padding: EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _line)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: _teal, size: 20),
      SizedBox(width: 8),
      Flexible(child: Text(label,
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _ink, fontSize: 12))),
      SizedBox(width: 7),
      Icon(Icons.keyboard_arrow_down_rounded, color: _ink, size: 19),
    ]),
  );

  Widget _mobileLayout() => Column(children: [
    Container(
      padding: EdgeInsets.fromLTRB(18, 9, 17, 7),
      child: Row(children: [
        Expanded(child: _brandRow(mobile: true)),
        IconButton(onPressed: _showNotifications, tooltip: 'Notifications (preview)',
          icon: Icon(Icons.notifications_none_rounded,
              color: _teal, size: 26)),
      ]),
    ),
    Expanded(child: _admissionScroll(wide: false)),
    _mobileActions(),
  ]);

  Widget _admissionScroll({required bool wide}) => SingleChildScrollView(
    key: Key('admission-scroll'),
    padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 8 : 8,
        wide ? 24 : 16, 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeading(wide),
      SizedBox(height: wide ? 16 : 13),
      _progress(wide),
      SizedBox(height: 15),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: Column(children: [
            _mainStepPanel(),
            if (_step == AdmissionStep.student) ...[
              SizedBox(height: 12),
              _contactPanel(),
            ],
          ])),
          SizedBox(width: 15),
          Expanded(flex: 3, child: _sideChecklist()),
        ])
      else ...[
        _mainStepPanel(),
        if (_step == AdmissionStep.student) ...[
          SizedBox(height: 13),
          _contactPanel(),
        ],
        SizedBox(height: 14),
        _mobileDocumentsChecklist(),
      ],
      if (wide) ...[
        SizedBox(height: 16),
        _actions(),
      ],
    ]),
  );

  Widget _pageHeading(bool wide) => Row(children: [
    if (!wide)
      IconButton(
        key: Key('admission-back-button'),
        onPressed: _step == 0 ? _confirmExit : _previous,
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: _teal)),
    Container(width: 5, height: wide ? 49 : 53,
        decoration: BoxDecoration(
          color: Color(0xFF00A28E),
          borderRadius: BorderRadius.circular(6))),
    SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('New Admission', style: TextStyle(
          color: _teal, fontSize: wide ? 31 : 29,
          fontWeight: FontWeight.w900)),
        Text(wide
            ? '${widget.owner?.campuses.isNotEmpty == true
                ? widget.owner!.campuses.first.name : 'School / Campus'} • '
              '${widget.owner?.activeYearLabel ?? 'Academic year'}'
            : widget.owner?.campuses.isNotEmpty == true
              ? widget.owner!.campuses.first.name
              : 'School / Campus',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _ink, fontSize: 13)),
      ])),
    if (wide) ...[
      OutlinedButton.icon(
        key: Key('admission-save-draft-disabled'),
        onPressed: _canSaveDraft ? _saveDraft : null,
        icon: Icon(Icons.save_outlined),
        label: Text(_savingDraft ? 'Saving...' : 'Save Draft')),
      SizedBox(width: 10),
      FilledButton.icon(
        onPressed: null,
        icon: Icon(Icons.send_outlined),
        label: Text('Submit for Approval')),
      SizedBox(width: 10),
      OutlinedButton.icon(
        onPressed: _confirmExit,
        icon: Icon(Icons.close),
        label: Text('Cancel')),
    ] else
      Chip(
        avatar: Icon(Icons.description_outlined, color: _teal, size: 18),
        label: Text('Draft', style: TextStyle(
            color: _teal, fontWeight: FontWeight.w700)),
        backgroundColor: _warningSurface,
        side: BorderSide.none),
  ]);

  Widget _progress(bool wide) => _surfaceCard(
    padding: EdgeInsets.symmetric(
      horizontal: wide ? 15 : 7, vertical: wide ? 10 : 13),
    child: Row(children: [
      for (var i = 0; i < AdmissionStep.values.length; i++) ...[
        if (i > 0)
          Expanded(child: Container(height: 2, color: i <= _step
            ? _teal : Color(0xFFBFD1DA))),
        Flexible(flex: wide ? 3 : 2,
          child: InkWell(
            key: Key(wide ? 'step-tab-$i' : 'step-chip-$i'),
            // Debug builds can inspect every screen independently.
            // This does not mark any validation as passed or submit data.
            onTap: i <= _step || kDebugMode
              ? () => setState(() { _step = i; _error = null; })
              : null,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: wide ? 18 : 23,
                backgroundColor: i == _step
                    ? _teal : _surface,
                child: wide
                  ? Text('${i + 1}', style: TextStyle(
                      color: i == _step ? Colors.white : _ink,
                      fontWeight: FontWeight.w700))
                  : Icon(_stepIcon(AdmissionStep.values[i]),
                      color: i == _step ? Colors.white : _teal,
                      size: 22),
              ),
              SizedBox(height: 6),
              Text(AdmissionStep.values[i].label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  color: i == _step ? _teal : _ink,
                  fontWeight: i == _step
                      ? FontWeight.w800 : FontWeight.w500,
                  fontSize: wide ? 12 : 10)),
            ]),
          )),
      ],
    ]),
  );

  Widget _surfaceCard({required Widget child,
      EdgeInsetsGeometry padding = const EdgeInsets.all(15)}) => Container(
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: _line),
      boxShadow: [BoxShadow(color: Color(0x10046D7B),
        blurRadius: 11, offset: Offset(0, 4))]),
    child: Padding(padding: padding, child: child),
  );

  Widget _panelHeading(IconData icon, String text, {String? trailing}) =>
    Row(children: [
      Icon(icon, color: _teal, size: 25),
      SizedBox(width: 10),
      Expanded(child: Text(text, style: TextStyle(
        fontSize: 19, fontWeight: FontWeight.w900, color: _teal))),
      if (trailing != null)
        Text(trailing, style: TextStyle(
          fontSize: 12, color: _muted)),
    ]);

  Widget _mainStepPanel() => _surfaceCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(_stepIcon(AdmissionStep.values[_step]),
            switch (AdmissionStep.values[_step]) {
              AdmissionStep.student => 'Student Details',
              AdmissionStep.guardians => 'Guardian Details',
              AdmissionStep.academic => 'Academic Placement',
              AdmissionStep.documents => 'Required Documents',
              AdmissionStep.fees => 'Fee Setup',
              AdmissionStep.review => 'Review Application',
            }, trailing: 'Step ${_step + 1} of 6'),
        Divider(height: 21, color: _line),
        if (_error != null) ...[
          Container(
            key: Key('admission-validation-error'),
            padding: EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: _warningSurface,
              borderRadius: BorderRadius.circular(9)),
            child: Text(_error!, style: TextStyle(
              color: Color(0xFFB01D24), fontWeight: FontWeight.w600))),
          SizedBox(height: 10),
        ],
        _stepContent(),
      ]),
  );

  Widget _mobileDocumentsChecklist() => _surfaceCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _panelHeading(Icons.description_outlined, 'Required Documents',
          trailing: 'Sample / preview'),
      Divider(height: 15, color: _line),
      _checkRow('Birth Certificate', isRequired: true),
      _checkRow('Guardian Identity Document'),
      if (_draft.transferCertificateApplicable)
        _checkRow('Transfer Certificate'),
      SizedBox(height: 5),
      Text('Uploads and verification are not enabled.',
        style: TextStyle(fontSize: 11, color: _muted)),
    ],
  ));

  Widget _checkRow(String title, {bool isRequired = false}) => Padding(
    padding: EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(Icons.check_box_outline_blank,
          size: 18, color: _muted),
      SizedBox(width: 11),
      Expanded(child: Text(title,
          style: TextStyle(fontSize: 12))),
      if (isRequired)
        Text('*', style: TextStyle(color: Colors.red)),
    ]),
  );

  Widget _sideChecklist() => Column(children: [
    _surfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(Icons.checklist_outlined, 'Admission Checklist'),
        Divider(color: _line),
        for (final item in [
          'Birth Certificate',
          if (_draft.transferCertificateApplicable) 'Transfer Certificate',
          'Guardian ID',
          'Class Placement',
          'Fee Setup'
        ]) _checkRow(item),
      ])),
    SizedBox(height: 11),
    _surfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(Icons.description_outlined, 'Required Documents'),
        Divider(color: _line),
        for (final item in _draft.requiredDocumentNames)
          ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.description_outlined,
                color: _teal, size: 19),
            title: Text(item, style: TextStyle(fontSize: 12)),
            trailing: Text('Pending', style: TextStyle(
              color: Color(0xFFB47713), fontSize: 11)),
          ),
      ])),
    SizedBox(height: 11),
    _surfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(Icons.school_outlined, 'Admission Status'),
        Divider(color: _line),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: _pale,
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.hourglass_top_outlined, color: _teal),
            SizedBox(width: 10),
            Expanded(child: Text('Draft (In Progress)',
              style: TextStyle(color: _teal, fontWeight: FontWeight.w800))),
          ]),
        ),
        SizedBox(height: 8),
        Text(_savedDraft == null
          ? 'No confirmed draft saved. Uploads and verification are pending.'
          : 'Saved draft ${_savedDraft!.id}; revision ${_savedDraft!.revision}. Not submitted.',
          style: TextStyle(fontSize: 12)),
      ])),
  ]);

  Widget _mobileActions() => Container(
    padding: EdgeInsets.fromLTRB(15, 11, 15, 12),
    decoration: BoxDecoration(color: _surface,
        border: Border(top: BorderSide(color: _line))),
    child: Row(children: [
      Expanded(child: OutlinedButton.icon(
        key: Key('admission-save-draft-disabled'),
        onPressed: _canSaveDraft ? _saveDraft : null,
        icon: Icon(Icons.save_outlined),
        label: Text(_savingDraft ? 'Saving...' : 'Save Draft'))),
      SizedBox(width: 11),
      Expanded(child: _step == AdmissionStep.review
        ? FilledButton.icon(
            key: Key('wizard-submit-disabled'),
            onPressed: null,
            icon: Icon(Icons.lock_outline),
            label: Text('Submit unavailable'))
        : FilledButton.icon(
            key: Key('wizard-next'),
            onPressed: _next,
            icon: Icon(Icons.arrow_forward),
            label: Text('Next Step'))),
    ]),
  );

  Widget _footerBar() => Container(
    height: 39,
    color: Color(0xFF005653),
    padding: EdgeInsets.symmetric(horizontal: 20),
    child: Row(children: [
      Icon(Icons.verified_user_outlined, color: Colors.white, size: 18),
      SizedBox(width: 9),
      Expanded(child: Text('Secure access for authorized staff only',
        style: TextStyle(color: Colors.white, fontSize: 11))),
      Text('Supa Model School v1.0.0',
        style: TextStyle(color: Colors.white, fontSize: 11)),
    ]),
  );

  Widget _stepContent() => switch (AdmissionStep.values[_step]) {
        AdmissionStep.student => _studentFields(),
        AdmissionStep.guardians => _guardianFields(),
        AdmissionStep.academic => _academicFields(),
        AdmissionStep.documents => _documentFields(),
        AdmissionStep.fees => _feeFields(),
        AdmissionStep.review => _reviewFields(),
      };


  Widget _styledField({
    required String label,
    required IconData icon,
    required ValueChanged<String> onChanged,
    String initialValue = '',
    Key? key,
    String? hint,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(icon, color: _teal, size: 17),
      SizedBox(width: 7),
      Flexible(child: Text(label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
          color: _ink))),
      if (isRequired) Text(' *', style: TextStyle(color: Colors.red)),
    ]),
    SizedBox(height: 6),
    TextFormField(
      key: key, initialValue: initialValue,
      onChanged: onChanged, maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder()),
    ),
  ]);

  Widget _styledChoice({
    required String label,
    required IconData icon,
    required String? current,
    required Map<String, String> options,
    required ValueChanged<String?> onChanged,
    bool isRequired = false,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [
      Icon(icon, color: _teal, size: 17),
      SizedBox(width: 7),
      Text(label, style: TextStyle(fontSize: 12,
        fontWeight: FontWeight.w700, color: _ink)),
      if (isRequired) Text(' *', style: TextStyle(color: Colors.red)),
    ]),
    SizedBox(height: 6),
    _choice(label: 'Choose $label', current: current,
      choices: options, onChanged: onChanged),
  ]);

  Widget _dobField() => Column(crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Icon(Icons.calendar_month_outlined, size: 17, color: _teal),
        SizedBox(width: 7),
        Text('Date of Birth', style: TextStyle(fontSize: 12,
          fontWeight: FontWeight.w700, color: _ink)),
        Text(' *', style: TextStyle(color: Colors.red)),
      ]),
      SizedBox(height: 6),
      SizedBox(height: 43, child: OutlinedButton.icon(
        key: Key('date-of-birth'),
        onPressed: _chooseBirthDate,
        icon: Icon(Icons.calendar_today_outlined, size: 17),
        label: Text(_dateLabel(_draft.dateOfBirth),
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12)),
      )),
    ]);

  Widget _photoPlaceholder() => Tooltip(
    message: 'Photo uploads require the private admission upload service.',
    child: Container(
      key: Key('admission-photo-placeholder'),
      width: 140, height: 134,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _pale,
        border: Border.all(color: Color(0xFFABDCD0),
          style: BorderStyle.solid)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 35, color: _teal),
          SizedBox(height: 8),
          Text('Photo Upload', style: TextStyle(
            fontWeight: FontWeight.w800, color: _teal, fontSize: 12)),
          SizedBox(height: 4),
          Text('Coming soon\nJPG, PNG • max 2 MB',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: _muted)),
        ],
      ),
    ),
  );

  Widget _studentFields() => LayoutBuilder(builder: (context, constraints) {
    final wide = constraints.maxWidth >= 660;
    final name = _styledField(
      key: Key('student-name'), label: 'Full Name',
      icon: Icons.person_outline, isRequired: true,
      hint: 'Student full name', initialValue: _draft.studentName,
      onChanged: (v) => _draft.studentName = v);
    final date = _dobField();
    final gender = _styledChoice(
      label: 'Gender', icon: Icons.groups_outlined,
      current: _draft.gender,
      options: {
        'unspecified': 'Prefer not to say',
        'male': 'Male', 'female': 'Female', 'other': 'Other',
      },
      onChanged: (v) => setState(() => _draft.gender = v ?? 'unspecified'));
    final previous = _styledField(
      key: Key('previous-school'),
      label: 'Previous School', icon: Icons.account_balance_outlined,
      hint: 'Previous school (if applicable)',
      initialValue: _draft.previousSchool,
      onChanged: (v) => setState(() => _draft.previousSchool = v));
    final nationality = _styledField(
      label: 'Nationality', icon: Icons.flag_outlined,
      hint: 'Nationality', initialValue: _draft.nationality,
      onChanged: (v) => _draft.nationality = v);
    final religion = _styledField(
      label: 'Religion (optional)', icon: Icons.account_balance_outlined,
      hint: 'Optional', initialValue: _draft.religion,
      onChanged: (v) => _draft.religion = v);
    final language = _styledField(
      label: 'Primary Language', icon: Icons.translate_outlined,
      hint: 'e.g. English / Urdu',
      initialValue: _draft.primaryLanguage,
      onChanged: (v) => _draft.primaryLanguage = v);
    final notes = _styledField(
      label: 'Notes (Optional)', icon: Icons.notes_outlined,
      maxLines: 2, initialValue: _draft.notes,
      hint: 'Additional student information',
      onChanged: (v) => _draft.notes = v);

    if (wide) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: Column(children: [
            Row(children: [
              Expanded(flex: 2, child: name),
              SizedBox(width: 12),
              Expanded(child: date),
            ]),
            SizedBox(height: 13),
            Row(children: [
              Expanded(child: gender),
              SizedBox(width: 12),
              Expanded(flex: 2, child: previous),
            ]),
          ])),
          SizedBox(width: 15),
          _photoPlaceholder(),
        ]),
        SizedBox(height: 13),
        Row(children: [
          Expanded(child: nationality),
          SizedBox(width: 12),
          Expanded(child: religion),
          SizedBox(width: 12),
          Expanded(child: language),
        ]),
        SizedBox(height: 13),
        notes,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 108, child: _photoPlaceholder()),
        SizedBox(width: 13),
        Expanded(child: name),
      ]),
      SizedBox(height: 14),
      Row(children: [
        Expanded(child: date),
        SizedBox(width: 12),
        Expanded(child: gender),
      ]),
      SizedBox(height: 14),
      previous,
      SizedBox(height: 14),
      Row(children: [
        Expanded(child: nationality),
        SizedBox(width: 12),
        Expanded(child: religion),
      ]),
      SizedBox(height: 14),
      language,
      SizedBox(height: 14),
      notes,
    ]);
  });

  Widget _contactPanel() => _surfaceCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _panelHeading(Icons.perm_contact_calendar_outlined,
          'Contact / Identity Information'),
      Divider(height: 20, color: _line),
      LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 560;
        final birth = _styledField(
          label: 'Birth Certificate No.', icon: Icons.description_outlined,
          initialValue: _draft.birthCertificateNumber,
          onChanged: (v) => _draft.birthCertificateNumber = v);
        final identity = _styledField(
          label: 'B-Form / Identity No. (if applicable)',
          icon: Icons.badge_outlined, initialValue: _draft.identityNumber,
          onChanged: (v) => _draft.identityNumber = v);
        return Column(children: [
          if (wide)
            Row(children: [
              Expanded(child: birth), SizedBox(width: 12),
              Expanded(child: identity),
            ])
          else ...[
            birth, SizedBox(height: 12), identity,
          ],
          SizedBox(height: 12),
          _styledField(label: 'Address', icon: Icons.location_on_outlined,
            initialValue: _draft.address,
            onChanged: (v) => _draft.address = v),
          SizedBox(height: 12),
          Row(children: [
            Expanded(child: _styledField(
              label: 'City', icon: Icons.location_city_outlined,
              initialValue: _draft.city,
              onChanged: (v) => _draft.city = v)),
            SizedBox(width: 12),
            Expanded(child: _styledField(
              label: 'Emergency Contact', icon: Icons.call_outlined,
              keyboardType: TextInputType.phone,
              initialValue: _draft.emergencyContact,
              onChanged: (v) => _draft.emergencyContact = v)),
          ]),
        ]);
      }),
    ]),
  );

  Widget _guardianFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Parent / Guardian Information',
        style: TextStyle(color: _teal, fontWeight: FontWeight.w800,
          fontSize: 15)),
      SizedBox(height: 6),
      Text('One primary contact is required. Other guardians can '
        'be added for the same student.',
        style: TextStyle(color: _muted, fontSize: 12)),
      SizedBox(height: 14),
      for (var i = 0; i < _draft.guardians.length; i++)
        _guardianCard(i, _draft.guardians[i]),
      SizedBox(height: 4),
      Align(alignment: Alignment.centerLeft, child:
        OutlinedButton.icon(
          key: Key('admission-add-guardian'),
          onPressed: _draft.guardians.length >= 8
            ? null : () => setState(() {
                _draft.guardians.add(
                  GuardianDraft(localId: _nextGuardianId++));
              }),
          icon: Icon(Icons.person_add_alt_1_outlined),
          label: Text('Add Another Guardian'),
        )),
    ],
  );

  Widget _guardianCard(int index, GuardianDraft guardian) => Container(
    key: ValueKey('guardian-${guardian.localId}'),
    margin: EdgeInsets.only(bottom: 12),
    padding: EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: _subSurface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.groups_outlined, color: _teal),
        SizedBox(width: 8),
        Expanded(child: Text('Guardian ${index + 1}',
          style: TextStyle(color: _teal,
            fontWeight: FontWeight.w800, fontSize: 15))),
        if (_draft.guardians.length > 1)
          IconButton(
            tooltip: 'Remove guardian',
            key: Key('remove-guardian-${guardian.localId}'),
            onPressed: () => setState(
              () => _draft.guardians.removeAt(index)),
            icon: Icon(Icons.delete_outline, color: Colors.redAccent)),
      ]),
      SizedBox(height: 12),
      _styledField(
        key: Key('guardian-name-${guardian.localId}'),
        label: 'Full Name', isRequired: true,
        icon: Icons.person_outline,
        initialValue: guardian.fullName,
        onChanged: (v) => guardian.fullName = v),
      SizedBox(height: 12),
      LayoutBuilder(builder: (context, bounds) {
        final relationship = _styledChoice(
          label: 'Relationship', icon: Icons.people_outline,
          current: guardian.relationship,
          options: {
            'father': 'Father', 'mother': 'Mother',
            'guardian': 'Guardian', 'other': 'Other',
          },
          onChanged: (v) => setState(
            () => guardian.relationship = v ?? 'guardian'));
        final phone = _styledField(
          key: Key('guardian-phone-${guardian.localId}'),
          label: guardian.isPrimary
              ? 'Primary Guardian Phone' : 'Phone Number',
          icon: Icons.call_outlined,
          isRequired: guardian.isPrimary,
          keyboardType: TextInputType.phone,
          initialValue: guardian.phone,
          onChanged: (v) => guardian.phone = v);
        return bounds.maxWidth >= 440
          ? Row(children: [
              Expanded(child: relationship),
              SizedBox(width: 12),
              Expanded(child: phone),
            ])
          : Column(children: [
              relationship, SizedBox(height: 12), phone,
            ]);
      }),
      SizedBox(height: 7),
      Wrap(spacing: 10, runSpacing: 0, children: [
        SizedBox(width: 210, child: CheckboxListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('Primary Contact', style: TextStyle(fontSize: 12)),
          value: guardian.isPrimary,
          onChanged: (selected) => setState(() {
            if (selected ?? false) {
              for (final person in _draft.guardians) {
                person.isPrimary = identical(person, guardian);
              }
            } else {
              guardian.isPrimary = false;
            }
          }),
        )),
        SizedBox(width: 190, child: CheckboxListTile(
          dense: true, contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text('Legal Guardian', style: TextStyle(fontSize: 12)),
          value: guardian.isLegalGuardian,
          onChanged: (selected) => setState(
            () => guardian.isLegalGuardian = selected ?? false),
        )),
      ]),
    ]),
  );

  Widget _academicFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Assign the academic year, campus, class and section.',
        style: TextStyle(color: _muted, fontSize: 12)),
      SizedBox(height: 14),
      if (!_academicReady)
        Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _warningSurface,
            border: Border.all(color: Color(0xFFF4D6A7)),
            borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.info_outline, color: Color(0xFF9A6D11)),
            SizedBox(width: 10),
            Expanded(child: Text(
              'No authorized academic options are available. '
              'Sign in as Owner, complete school setup, and create '
              'classes and sections first.',
              style: TextStyle(fontSize: 12))),
          ]),
        )
      else ...[
        Text('Academic choices are loaded from your verified '
          'school records. Only the active academic year is shown.',
          style: TextStyle(fontSize: 12)),
        SizedBox(height: 13),
        LayoutBuilder(builder: (context, c) {
          final campus = _choice(
            key: Key('admission-campus-choice'),
            label: 'Campus *', current: _draft.campusId,
            choices: _campusChoices,
            onChanged: _chooseCampus);
          final year = _choice(
            key: Key('admission-year-choice'),
            label: 'Academic Year *', current: _draft.academicYearId,
            choices: _yearChoices,
            onChanged: (_) {});
          if (c.maxWidth >= 520) {
            return Row(children: [
              Expanded(child: campus),
              SizedBox(width: 13),
              Expanded(child: year),
            ]);
          }
          return Column(children: [
            campus, SizedBox(height: 12), year,
          ]);
        }),
        if (_academicLoading) ...[
          SizedBox(height: 13),
          LinearProgressIndicator(
            key: Key('admission-classes-loading')),
        ],
        if (_academicError != null) ...[
          SizedBox(height: 13),
          Text(_academicError!,
            key: Key('admission-classes-error'),
            style: TextStyle(color: Color(0xFFB6232C))),
          TextButton.icon(
            onPressed: _draft.campusId == null
              ? null : () => _loadClasses(_draft.campusId!),
            icon: Icon(Icons.refresh),
            label: Text('Retry class lookup')),
        ],
        SizedBox(height: 13),
        LayoutBuilder(builder: (context, c) {
          final schoolClass = _choice(
            key: ValueKey('class-choice-${_draft.campusId}-'
              '${_draft.academicYearId}-${_academicClasses.length}'),
            label: 'Class *',
            current: _draft.classId,
            choices: _classChoices,
            onChanged: (value) => setState(() {
              _draft.classId = value;
              _draft.sectionId = null;
              _error = null;
            }),
          );
          final section = _choice(
            key: ValueKey('section-choice-${_draft.classId}'),
            label: 'Section (optional)',
            current: _draft.sectionId,
            choices: _sectionChoices,
            onChanged: (value) => setState(() {
              _draft.sectionId = value;
              _error = null;
            }),
          );
          if (c.maxWidth >= 520) {
            return Row(children: [
              Expanded(child: schoolClass),
              SizedBox(width: 13),
              Expanded(child: section),
            ]);
          }
          return Column(children: [
            schoolClass, SizedBox(height: 12), section,
          ]);
        }),
        if (!_academicLoading && _draft.campusId != null &&
            _academicError == null && _academicClasses.isEmpty) ...[
          SizedBox(height: 10),
          Text('No classes exist for this campus and academic year. '
            'Create them in Owner → Academic Setup.',
            style: TextStyle(fontSize: 12, color: Color(0xFF9A6D11))),
        ],
      ],
      SizedBox(height: 18),
      Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(color: _pale,
          borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(Icons.verified_user_outlined, color: _teal),
          SizedBox(width: 10),
          Expanded(child: Text('A permanent registration/admission number '
            'will be generated by the trusted server after Principal approval. '
            'This screen does not create a student.',
            style: TextStyle(fontSize: 12))),
        ]),
      ),
    ],
  );

  Widget _documentFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Required Certificate Uploads',
        style: TextStyle(color: _teal, fontSize: 15,
          fontWeight: FontWeight.w900)),
      SizedBox(height: 7),
      Text('Documents are awaiting secure upload and verification. '
        'No file has been stored from this preview.',
        style: TextStyle(fontSize: 12, color: _muted)),
      SizedBox(height: 14),
      for (final name in _draft.requiredDocumentNames)
        Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(11),
            color: _subSurface),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                color: _pale, borderRadius: BorderRadius.circular(9)),
              child: Icon(Icons.description_outlined,
                color: _teal)),
            SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 13)),
                SizedBox(height: 4),
                Text('Not uploaded • Not verified',
                  style: TextStyle(
                    color: _muted, fontSize: 11)),
              ],
            )),
            Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: Color(0xFFFFE9C5),
              side: BorderSide.none,
              label: Text('Pending',
                style: TextStyle(
                  color: Color(0xFF986313), fontSize: 11))),
          ]),
        ),
      Container(
        key: Key('admission-upload-disabled'),
        padding: EdgeInsets.symmetric(vertical: 19, horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Color(0xFFB3CDD8)),
          color: _subSurface,
          borderRadius: BorderRadius.circular(12)),
        child: Column(children: [
          Icon(Icons.cloud_upload_outlined, size: 39, color: _teal),
          SizedBox(height: 5),
          Text('Secure document upload coming soon',
            textAlign: TextAlign.center,
            style: TextStyle(color: _teal,
              fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('PDF, JPG, PNG • verification by authorized staff',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted, fontSize: 11)),
        ]),
      ),
      SizedBox(height: 16),
      Text('Conditional Document Submission',
        style: TextStyle(color: _teal, fontSize: 15,
          fontWeight: FontWeight.w900)),
      SizedBox(height: 6),
      Text('Where required certificates are missing, the school may '
        'permit a deadline up to two calendar months. '
        'An overdue certificate never automatically deletes the student.',
        style: TextStyle(fontSize: 12, color: _muted)),
      SizedBox(height: 13),
      OutlinedButton.icon(
        key: Key('document-deadline'),
        onPressed: _chooseDocumentDeadline,
        icon: Icon(Icons.calendar_month_outlined, color: _teal),
        label: Text('Submission Deadline *: '
          '${_dateLabel(_draft.missingDocumentsDueOn)}'),
      ),
      SizedBox(height: 13),
      _styledField(
        key: Key('conditional-reason'),
        label: 'Reason for Outstanding Documents', isRequired: true,
        icon: Icons.notes_outlined,
        initialValue: _draft.conditionalReason,
        maxLines: 3,
        onChanged: (v) => _draft.conditionalReason = v),
      SizedBox(height: 12),
      Text('Deadline decisions and document verification will be '
        'audited when the trusted admissions service is enabled.',
        style: TextStyle(fontSize: 11, color: _muted)),
    ],
  );

  Widget _feeFields() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Admission Fee Preferences',
        style: TextStyle(color: _teal,
          fontWeight: FontWeight.w900, fontSize: 15)),
      SizedBox(height: 6),
      Text('Fee amounts and payment verification will come from '
        'authorized school plans. No money is collected on this screen.',
        style: TextStyle(fontSize: 12, color: _muted)),
      SizedBox(height: 15),
      Container(
        padding: EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _subSurface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.savings_outlined, color: _teal),
            SizedBox(width: 9),
            Text('Admission Fee Status', style: TextStyle(
              color: _teal, fontWeight: FontWeight.w800)),
          ]),
          SizedBox(height: 12),
          _choice(label: 'Select admission fee status',
            current: _draft.admissionFeeStatus,
            choices: {
              'not_recorded': 'Skip / Not recorded',
              'unpaid': 'Unpaid',
              'paid': 'Paid (requires verification)',
            },
            onChanged: (v) => setState(
              () => _draft.admissionFeeStatus = v ?? 'not_recorded')),
          SizedBox(height: 8),
          Text('Selecting Paid does not record a payment or issue a receipt.',
            style: TextStyle(fontSize: 11, color: _muted)),
        ]),
      ),
      SizedBox(height: 12),
      Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(color: _subSurface,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(11)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.directions_bus_outlined, color: _teal),
            title: Text('School Transport', style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text('Request transport for this student',
              style: TextStyle(fontSize: 11)),
            value: _draft.usesTransport,
            onChanged: (v) => setState(() => _draft.usesTransport = v),
          ),
          if (_draft.usesTransport) ...[
            _styledField(label: 'Transport Notes',
              icon: Icons.notes_outlined,
              initialValue: _draft.transportNotes,
              onChanged: (v) => _draft.transportNotes = v),
            SizedBox(height: 10),
          ],
          Divider(height: 12, color: _line),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(Icons.percent_outlined, color: _teal),
            title: Text('Scholarship / Discount Request',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            subtitle: Text('Requires an authorized discount rule',
              style: TextStyle(fontSize: 11)),
            value: _draft.requestsDiscount,
            onChanged: (v) => setState(() => _draft.requestsDiscount = v),
          ),
          if (_draft.requestsDiscount)
            _styledField(label: 'Discount Request Notes',
              icon: Icons.notes_outlined,
              initialValue: _draft.discountNotes,
              onChanged: (v) => _draft.discountNotes = v),
        ]),
      ),
      SizedBox(height: 13),
      Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _pale, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(Icons.info_outline, color: _teal),
          SizedBox(width: 10),
          Expanded(child: Text('Tuition, transport and other fee categories '
            'will be calculated after an approved enrollment. '
            'No financial ledger entry has been created.',
            style: TextStyle(fontSize: 12))),
        ]),
      ),
    ],
  );

  Widget _reviewSection(String title, IconData icon, List<Widget> rows) =>
    Container(
      margin: EdgeInsets.only(bottom: 13),
      padding: EdgeInsets.all(13),
      decoration: BoxDecoration(
        border: Border.all(color: _line),
        color: _subSurface,
        borderRadius: BorderRadius.circular(11)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: _teal, size: 21),
          SizedBox(width: 9),
          Expanded(child: Text(title,
            style: TextStyle(color: _teal,
              fontSize: 15, fontWeight: FontWeight.w900))),
        ]),
        Divider(height: 16, color: _line),
        ...rows,
      ]),
    );

  Widget _reviewFields() {
    final warning = _draft.validateStep(AdmissionStep.review);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Confirm the application details below before forwarding '
        'to the Principal.',
        style: TextStyle(fontSize: 12, color: _muted)),
      SizedBox(height: 13),
      if (warning != null) ...[
        Container(
          padding: EdgeInsets.all(11),
          decoration: BoxDecoration(color: _warningSurface,
            borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            Icon(Icons.warning_amber_outlined,
                color: Color(0xFF9C6B12)),
            SizedBox(width: 9),
            Expanded(child: Text('Additional information required: $warning',
              style: TextStyle(fontSize: 12))),
          ]),
        ),
        SizedBox(height: 12),
      ],
      _reviewSection('Student Information', Icons.person_outline, [
        _summaryRow('Full Name', _draft.studentName),
        _summaryRow('Date of Birth', _dateLabel(_draft.dateOfBirth)),
        _summaryRow('Gender', _draft.gender),
        _summaryRow('Previous School',
          _draft.previousSchool.trim().isEmpty
            ? 'Not applicable' : _draft.previousSchool),
        _summaryRow('Nationality', _draft.nationality),
        _summaryRow('Primary Language', _draft.primaryLanguage),
        _summaryRow('Notes', _draft.notes),
      ]),
      _reviewSection('Guardian Contacts', Icons.groups_outlined, [
        for (final person in _draft.guardians)
          _summaryRow(person.isPrimary ? 'Primary Guardian' : 'Guardian',
            '${person.fullName} • ${person.relationship} • '
            '${person.phone.isEmpty ? 'No phone' : person.phone}'),
      ]),
      _reviewSection('Academic Placement', Icons.school_outlined, [
        _summaryRow('Campus', _campusChoices[_draft.campusId] ?? 'Not selected'),
        _summaryRow('Academic Year',
          _yearChoices[_draft.academicYearId] ?? 'Not selected'),
        _summaryRow('Class',
          _classChoices[_draft.classId] ?? 'Not selected'),
        _summaryRow('Section',
          _sectionChoices[_draft.sectionId] ?? 'Unassigned'),
      ]),
      _reviewSection('Documents', Icons.description_outlined, [
        for (final name in _draft.requiredDocumentNames)
          _summaryRow(name, 'Not uploaded / unverified'),
        _summaryRow('Conditional Deadline',
          _dateLabel(_draft.missingDocumentsDueOn)),
        _summaryRow('Reason', _draft.conditionalReason),
      ]),
      _reviewSection('Fee Preferences', Icons.savings_outlined, [
        _summaryRow('Admission Fee', _draft.admissionFeeStatus),
        _summaryRow('Transport',
          _draft.usesTransport ? 'Requested' : 'Not requested'),
        _summaryRow('Scholarship / Discount',
          _draft.requestsDiscount ? 'Requested' : 'Not requested'),
      ]),
      Container(
        padding: EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _warningSurface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Color(0xFFF3D8A3))),
        child: Row(children: [
          Icon(Icons.lock_outline, color: Color(0xFF906115)),
          SizedBox(width: 12),
          Expanded(child: Text(
            _savedDraft == null
            ? 'Save Draft stores the core applicant, guardian, and academic fields in Supabase. Optional notes, fee preferences, and document deadlines are not saved yet. Submission and Principal approval remain disabled.'
            : 'Confirmed draft saved in Supabase. This is NOT a submitted or approved admission. Additional notes, fee preferences, and documents are not saved yet.',
            style: TextStyle(fontSize: 12))),
        ]),
      ),
    ]);
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 155,
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Text(value.isEmpty ? 'Not provided' : value)),
          ],
        ),
      );

  Widget _choice({
    Key? key,
    required String label,
    required String? current,
    required Map<String, String> choices,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: choices.containsKey(current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: OutlineInputBorder()),
      items: [
        for (final entry in choices.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: choices.isEmpty ? null : onChanged,
    );
  }

  Widget _actions() => Row(children: [
    Expanded(child: OutlinedButton.icon(
      onPressed: _step == 0 ? null : _previous,
      icon: Icon(Icons.arrow_back),
      label: Text('Back'),
    )),
    SizedBox(width: 13),
    Expanded(child: _step < AdmissionStep.values.length - 1
      ? FilledButton.icon(
          key: Key('wizard-next'),
          onPressed: _next,
          icon: Icon(Icons.arrow_forward),
          iconAlignment: IconAlignment.end,
          label: Text('Next Step'))
      : FilledButton.icon(
          key: Key('wizard-submit-disabled'),
          onPressed: null,
          icon: Icon(Icons.lock_outline),
          label: Text('Submit unavailable')),
    ),
  ]);

}
