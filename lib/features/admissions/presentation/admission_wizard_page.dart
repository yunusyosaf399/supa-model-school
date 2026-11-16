import 'package:flutter/material.dart';

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
    this.initialStep = AdmissionStep.student,
  });

  /// Widget-test seam; production navigation always starts at Student.
  @visibleForTesting
  final AdmissionStep initialStep;

  /// Null means design preview; never substitute fictional academic IDs.
  final OwnerAccess? owner;
  final AcademicStructureRepository? academicRepository;

  @override
  State<AdmissionWizardPage> createState() => _AdmissionWizardPageState();
}

class _AdmissionWizardPageState extends State<AdmissionWizardPage> {
  final AdmissionDraft _draft = AdmissionDraft();
  late int _step;
  int _nextGuardianId = 2;
  String? _error;
  bool _allowExit = false;
  List<SchoolClassRecord> _academicClasses = const [];
  bool _academicLoading = false;
  String? _academicError;
  int _academicLoadVersion = 0;

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
      _academicClasses = const [];
      _academicLoading = false;
      _academicError = null;
      _error = null;
    });
    if (id != null) _loadClasses(id);
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
        _academicClasses = const [];
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
          currentDay.add(const Duration(days: 60)),
      firstDate: currentDay,
      lastDate: DateTime(today.year + 3, today.month, today.day),
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

  Future<void> _confirmExit() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard admission preview?'),
        content: const Text(
          'Only academic options may be read from your school database. '
          'No admission details have been saved. All entered information '
          'will be lost when you leave.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Continue editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Discard preview'),
          ),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    setState(() => _allowExit = true);
    // PopScope must rebuild with canPop=true before popping the route.
    // Otherwise a second interception can reopen the confirmation dialog.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }


  static const _teal = Color(0xFF00635D);
  static const _pale = Color(0xFFE7F5F6);
  static const _ink = Color(0xFF193745);
  static const _line = Color(0xFFD5E2E8);

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
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: _teal),
        scaffoldBackgroundColor: const Color(0xFFF0F8FD),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 13, vertical: 12),
          border: OutlineInputBorder(
            borderSide: const BorderSide(color: _line),
            borderRadius: BorderRadius.circular(7)),
        ),
      ),
      child: PopScope(
        canPop: _allowExit,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          key: const Key('admission-wizard-screen'),
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
      const SizedBox(width: 11),
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

  Widget _desktopLayout() => Column(children: [
    Container(
      height: 37,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_teal, Color(0xFF004D4A)])),
      child: const Row(children: [
        Icon(Icons.school_outlined, size: 20, color: Colors.white),
        SizedBox(width: 10),
        Text('Supa Model School', style: TextStyle(
            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        SizedBox(width: 12),
        Text('│  School Management System', style: TextStyle(
            color: Colors.white, fontSize: 12)),
      ]),
    ),
    Expanded(child: Row(children: [
      _sidebar(),
      Expanded(child: Column(children: [
        _desktopToolbar(),
        Expanded(child: _admissionScroll(wide: true)),
      ])),
    ])),
  ]);

  Widget _sidebar() {
    const names = ['Dashboard', 'Students', 'Admissions', 'Fees',
      'Attendance', 'Employees', 'Payroll', 'Expenses',
      'Reports', 'Sync Center', 'Settings'];
    const icons = [Icons.home_outlined, Icons.groups_outlined,
      Icons.school_outlined, Icons.savings_outlined,
      Icons.calendar_month_outlined, Icons.people_outline,
      Icons.account_balance_wallet_outlined,
      Icons.receipt_long_outlined, Icons.bar_chart_outlined,
      Icons.sync_outlined, Icons.settings_outlined];
    return Container(
      key: const Key('admission-desktop-sidebar'),
      width: 244,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: _line))),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 13, 12, 17),
          child: Column(children: [
            const SchoolMark(size: 68),
            const SizedBox(height: 5),
            const Text('Supa Model School',
              style: TextStyle(color: _teal, fontWeight: FontWeight.w900,
                  fontSize: 17)),
            const Text('School Management System',
              style: TextStyle(fontSize: 11, color: _ink)),
            const Divider(height: 24),
          ])),
        Expanded(child: ListView(padding: const EdgeInsets.symmetric(
            horizontal: 13), children: [
          for (var i = 0; i < names.length; i++)
            Container(
              height: 40, margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: i == 2 ? const LinearGradient(colors: [
                  Color(0xFF029B8A), Color(0xFF005B55)]) : null),
              child: Row(children: [
                const SizedBox(width: 16),
                Icon(icons[i], size: 21,
                  color: i == 2 ? Colors.white : _ink),
                const SizedBox(width: 13),
                Text(names[i], style: TextStyle(
                  color: i == 2 ? Colors.white : _ink,
                  fontWeight: i == 2 ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 13)),
              ]),
            ),
        ])),
      ]),
    );
  }

  Widget _desktopToolbar() => Container(
    height: 73,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    child: Row(children: [
      Expanded(flex: 4, child: OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.search_outlined),
        label: const Align(alignment: Alignment.centerLeft,
          child: Text('Search students, staff, invoices, etc...',
            overflow: TextOverflow.ellipsis)),
      )),
      const SizedBox(width: 14),
      _topPill(Icons.account_balance_outlined,
          widget.owner?.campuses.isNotEmpty == true
            ? widget.owner!.campuses.first.name : 'School / Campus'),
      const SizedBox(width: 12),
      _topPill(Icons.calendar_month_outlined,
          widget.owner?.activeYearLabel ?? 'Academic Year'),
      const SizedBox(width: 13),
      const Icon(Icons.notifications_none_rounded, size: 26, color: _teal),
      const SizedBox(width: 14),
      const CircleAvatar(radius: 18,
          child: Icon(Icons.person_outline)),
      const SizedBox(width: 8),
      const Flexible(child: Text('Administrator',
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
    ]),
  );

  Widget _topPill(IconData icon, String label) => Container(
    constraints: const BoxConstraints(maxWidth: 200),
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(color: Colors.white,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: _line)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: _teal, size: 20),
      const SizedBox(width: 8),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12))),
      const Icon(Icons.keyboard_arrow_down, size: 18),
    ]),
  );

  Widget _mobileLayout() => Column(children: [
    Container(
      padding: const EdgeInsets.fromLTRB(18, 9, 17, 7),
      child: Row(children: [
        Expanded(child: _brandRow(mobile: true)),
        IconButton(onPressed: () {}, tooltip: 'Notifications (preview)',
          icon: const Icon(Icons.notifications_none_rounded,
              color: _teal, size: 26)),
      ]),
    ),
    Expanded(child: _admissionScroll(wide: false)),
    _mobileActions(),
  ]);

  Widget _admissionScroll({required bool wide}) => SingleChildScrollView(
    key: const Key('admission-scroll'),
    padding: EdgeInsets.fromLTRB(wide ? 24 : 16, wide ? 8 : 8,
        wide ? 24 : 16, 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _pageHeading(wide),
      SizedBox(height: wide ? 16 : 13),
      _progress(wide),
      const SizedBox(height: 15),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 7, child: _mainStepPanel()),
          const SizedBox(width: 15),
          Expanded(flex: 3, child: _sideChecklist()),
        ])
      else ...[
        _mainStepPanel(),
        const SizedBox(height: 14),
        _mobileDocumentsChecklist(),
      ],
      if (wide) ...[
        const SizedBox(height: 16),
        _actions(),
      ],
    ]),
  );

  Widget _pageHeading(bool wide) => Row(children: [
    if (!wide)
      IconButton(
        key: const Key('admission-back-button'),
        onPressed: _step == 0 ? _confirmExit : _previous,
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: _teal)),
    Container(width: 5, height: wide ? 49 : 53,
        decoration: BoxDecoration(
          color: const Color(0xFF00A28E),
          borderRadius: BorderRadius.circular(6))),
    const SizedBox(width: 14),
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
            style: const TextStyle(color: _ink, fontSize: 13)),
      ])),
    if (wide) ...[
      OutlinedButton.icon(
        key: const Key('admission-save-draft-disabled'),
        onPressed: null, icon: const Icon(Icons.save_outlined),
        label: const Text('Save Draft')),
      const SizedBox(width: 10),
      FilledButton.icon(
        onPressed: null,
        icon: const Icon(Icons.send_outlined),
        label: const Text('Submit for Approval')),
      const SizedBox(width: 10),
      OutlinedButton.icon(
        onPressed: _confirmExit,
        icon: const Icon(Icons.close),
        label: const Text('Cancel')),
    ] else
      Chip(
        avatar: const Icon(Icons.edit_document, color: _teal, size: 18),
        label: const Text('Draft', style: TextStyle(
            color: _teal, fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFFFF0D4),
        side: BorderSide.none),
  ]);

  Widget _progress(bool wide) => _surfaceCard(
    padding: EdgeInsets.symmetric(
      horizontal: wide ? 15 : 7, vertical: wide ? 10 : 13),
    child: Row(children: [
      for (var i = 0; i < AdmissionStep.values.length; i++) ...[
        if (i > 0)
          Expanded(child: Container(height: 2, color: i <= _step
            ? _teal : const Color(0xFFBFD1DA))),
        Flexible(flex: wide ? 3 : 2,
          child: InkWell(
            key: Key(wide ? 'step-tab-$i' : 'step-chip-$i'),
            onTap: i <= _step
              ? () => setState(() { _step = i; _error = null; })
              : null,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: wide ? 18 : 23,
                backgroundColor: i == _step
                    ? _teal : Colors.white,
                child: wide
                  ? Text('${i + 1}', style: TextStyle(
                      color: i == _step ? Colors.white : _ink,
                      fontWeight: FontWeight.w700))
                  : Icon(_stepIcon(AdmissionStep.values[i]),
                      color: i == _step ? Colors.white : _teal,
                      size: 22),
              ),
              const SizedBox(height: 6),
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: _line),
      boxShadow: const [BoxShadow(color: Color(0x10046D7B),
        blurRadius: 11, offset: Offset(0, 4))]),
    child: Padding(padding: padding, child: child),
  );

  Widget _panelHeading(IconData icon, String text, {String? trailing}) =>
    Row(children: [
      Icon(icon, color: _teal, size: 25),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(
        fontSize: 19, fontWeight: FontWeight.w900, color: _teal))),
      if (trailing != null)
        Text(trailing, style: const TextStyle(
          fontSize: 12, color: Color(0xFF63798A))),
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
        const Divider(height: 21, color: _line),
        if (_error != null) ...[
          Container(
            key: const Key('admission-validation-error'),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE9E7),
              borderRadius: BorderRadius.circular(9)),
            child: Text(_error!, style: const TextStyle(
              color: Color(0xFFB01D24), fontWeight: FontWeight.w600))),
          const SizedBox(height: 10),
        ],
        _stepContent(),
      ]),
  );

  Widget _mobileDocumentsChecklist() => _surfaceCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _panelHeading(Icons.description_outlined, 'Required Documents',
          trailing: 'Sample / preview'),
      const Divider(height: 15, color: _line),
      _checkRow('Birth Certificate', required: true),
      _checkRow('Guardian Identity Document'),
      if (_draft.transferCertificateApplicable)
        _checkRow('Transfer Certificate'),
      const SizedBox(height: 5),
      const Text('Uploads and verification are not enabled.',
        style: TextStyle(fontSize: 11, color: Color(0xFF617888))),
    ],
  ));

  Widget _checkRow(String title, {bool required = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      const Icon(Icons.check_box_outline_blank,
          size: 18, color: Color(0xFF8FA6B6)),
      const SizedBox(width: 11),
      Expanded(child: Text(title,
          style: const TextStyle(fontSize: 12))),
      if (required)
        const Text('*', style: TextStyle(color: Colors.red)),
    ]),
  );

  Widget _sideChecklist() => Column(children: [
    _surfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(Icons.checklist_outlined, 'Admission Checklist'),
        const Divider(color: _line),
        for (final item in [
          'Birth Certificate',
          if (_draft.transferCertificateApplicable) 'Transfer Certificate',
          'Guardian ID',
          'Class Placement',
          'Fee Setup'
        ]) _checkRow(item),
      ])),
    const SizedBox(height: 11),
    _surfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(Icons.description_outlined, 'Required Documents'),
        const Divider(color: _line),
        for (final item in _draft.requiredDocumentNames)
          ListTile(
            dense: true, contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined,
                color: _teal, size: 19),
            title: Text(item, style: const TextStyle(fontSize: 12)),
            trailing: const Text('Pending', style: TextStyle(
              color: Color(0xFFB47713), fontSize: 11)),
          ),
      ])),
    const SizedBox(height: 11),
    _surfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeading(Icons.school_outlined, 'Admission Status'),
        const Divider(color: _line),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFE2F7EE),
            borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.hourglass_top_outlined, color: _teal),
            SizedBox(width: 10),
            Expanded(child: Text('Draft (In Progress)',
              style: TextStyle(color: _teal, fontWeight: FontWeight.w800))),
          ]),
        ),
        const SizedBox(height: 8),
        const Text('No application has been saved. Uploads and '
          'verification are pending.',
          style: TextStyle(fontSize: 12)),
      ])),
  ]);

  Widget _mobileActions() => Container(
    padding: const EdgeInsets.fromLTRB(15, 11, 15, 12),
    decoration: const BoxDecoration(color: Colors.white,
        border: Border(top: BorderSide(color: _line))),
    child: Row(children: [
      Expanded(child: OutlinedButton.icon(
        key: const Key('admission-save-draft-disabled'),
        onPressed: null,
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save Draft'))),
      const SizedBox(width: 11),
      Expanded(child: _step == AdmissionStep.review
        ? FilledButton.icon(
            key: const Key('wizard-submit-disabled'),
            onPressed: null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Submit unavailable'))
        : FilledButton.icon(
            key: const Key('wizard-next'),
            onPressed: _next,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Next Step'))),
    ]),
  );

  Widget _footerBar() => Container(
    height: 39,
    color: const Color(0xFF005653),
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: const Row(children: [
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

  Widget _studentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Student identity', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('student-name'),
          initialValue: _draft.studentName,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Student full name *',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => _draft.studentName = value,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('date-of-birth'),
          onPressed: _chooseBirthDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Date of birth *: ${_dateLabel(_draft.dateOfBirth)}'),
        ),
        const SizedBox(height: 16),
        _choice(
          label: 'Gender (optional)',
          current: _draft.gender,
          choices: const {
            'unspecified': 'Prefer not to say',
            'male': 'Male',
            'female': 'Female',
            'other': 'Other',
          },
          onChanged: (value) => setState(() => _draft.gender = value!),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('previous-school'),
          initialValue: _draft.previousSchool,
          maxLength: 200,
          decoration: const InputDecoration(
            labelText: 'Previous school (if applicable)',
            helperText: 'Determines whether a transfer/leaving certificate is required.',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _draft.previousSchool = value,
        ),
      ],
    );
  }

  Widget _guardianFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Parent or guardian contacts',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Exactly one primary guardian is required for submission. '
            'A guardian may later be linked to several siblings.'),
        const SizedBox(height: 14),
        for (var i = 0; i < _draft.guardians.length; i++)
          _guardianCard(i, _draft.guardians[i]),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _draft.guardians.length >= 8
                ? null
                : () => setState(() => _draft.guardians.add(
                      GuardianDraft(localId: _nextGuardianId++),
                    )),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Add another guardian'),
          ),
        ),
      ],
    );
  }

  Widget _guardianCard(int index, GuardianDraft guardian) {
    return Card.outlined(
      key: ValueKey('guardian-${guardian.localId}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Guardian ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold))),
                if (_draft.guardians.length > 1)
                  IconButton(
                    key: Key('remove-guardian-${guardian.localId}'),
                    tooltip: 'Remove guardian',
                    onPressed: () => setState(() => _draft.guardians.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            TextFormField(
              key: Key('guardian-name-${guardian.localId}'),
              initialValue: guardian.fullName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name *',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => guardian.fullName = v,
            ),
            const SizedBox(height: 12),
            _choice(
              label: 'Relationship',
              current: guardian.relationship,
              choices: const {
                'father': 'Father',
                'mother': 'Mother',
                'guardian': 'Guardian',
                'other': 'Other',
              },
              onChanged: (v) => setState(() => guardian.relationship = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: Key('guardian-phone-${guardian.localId}'),
              initialValue: guardian.phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: guardian.isPrimary
                    ? 'Primary guardian phone *'
                    : 'Phone number',
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => guardian.phone = v,
            ),
            CheckboxListTile(
              title: const Text('Primary contact'),
              contentPadding: EdgeInsets.zero,
              value: guardian.isPrimary,
              onChanged: (selected) => setState(() {
                if (selected ?? false) {
                  for (final g in _draft.guardians) {
                    g.isPrimary = identical(g, guardian);
                  }
                } else {
                  guardian.isPrimary = false;
                }
              }),
            ),
            CheckboxListTile(
              title: const Text('Legal guardian'),
              contentPadding: EdgeInsets.zero,
              value: guardian.isLegalGuardian,
              onChanged: (selected) =>
                  setState(() => guardian.isLegalGuardian = selected ?? false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _academicFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Class and campus allocation',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (!_academicReady) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('No authorized academic options are available. '
                  'Sign in as Owner, complete school setup, and create '
                  'classes and sections before selecting a placement.'),
            ),
          ),
        ] else ...[
          const Text('The options below come from your school database. '
              'Only the active academic year is available for new admissions.'),
          const SizedBox(height: 16),
          _choice(
            key: const Key('admission-campus-choice'),
            label: 'Campus *',
            current: _draft.campusId,
            choices: _campusChoices,
            onChanged: _chooseCampus,
          ),
          const SizedBox(height: 16),
          _choice(
            key: const Key('admission-year-choice'),
            label: 'Academic year *',
            current: _draft.academicYearId,
            choices: _yearChoices,
            onChanged: (_) {}, // Server-selected active year only.
          ),
          if (_academicLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              key: Key('admission-classes-loading'),
            ),
          ],
          if (_academicError != null) ...[
            const SizedBox(height: 12),
            Text(_academicError!,
                key: const Key('admission-classes-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            TextButton.icon(
              onPressed: _draft.campusId == null
                  ? null : () => _loadClasses(_draft.campusId!),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry class lookup'),
            ),
          ],
          const SizedBox(height: 16),
          _choice(
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
          ),
          if (!_academicLoading && _draft.campusId != null &&
              _academicError == null && _academicClasses.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('No classes exist for this campus and academic year. '
                'Create them in Owner → Academic Setup.'),
          ],
          const SizedBox(height: 16),
          _choice(
            key: ValueKey('section-choice-${_draft.classId}'),
            label: 'Section (optional)',
            current: _draft.sectionId,
            choices: _sectionChoices,
            onChanged: (value) => setState(() {
              _draft.sectionId = value;
              _error = null;
            }),
          ),
        ],
        const SizedBox(height: 12),
        const Text('The permanent registration number will be generated by '
            'the trusted server after admission approval; nothing is '
            'submitted at this stage.'),
      ],
    );
  }

  Widget _documentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Required certificates',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Files cannot be uploaded or verified in this preview. '
            'All required certificates must be treated as outstanding.'),
        const SizedBox(height: 12),
        for (final name in _draft.requiredDocumentNames)
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(name),
            subtitle: const Text('Not uploaded or verified'),
            trailing: const Chip(label: Text('Outstanding')),
          ),
        const Divider(height: 24),
        const Text('Conditional documentation',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('School policy allows conditional admission with a deadline. '
            'A late document does not automatically cancel enrollment.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('document-deadline'),
          onPressed: _chooseDocumentDeadline,
          icon: const Icon(Icons.calendar_month_outlined),
          label: Text('Document deadline *: '
              '${_dateLabel(_draft.missingDocumentsDueOn)}'),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('conditional-reason'),
          initialValue: _draft.conditionalReason,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for conditional admission *',
            border: OutlineInputBorder(),
            helperText: 'Saved in the server audit trail when the backend is ready.',
          ),
          onChanged: (v) => _draft.conditionalReason = v,
        ),
        const SizedBox(height: 10),
        const Text('Verification and deadline extensions will require '
            'authorized server operations and separate audit records.'),
      ],
    );
  }

  Widget _feeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Fee preferences (no financial posting)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        const Text('Tuition and other fee amounts will come from approved '
            'campus/class plans. This screen does not collect money.'),
        const SizedBox(height: 16),
        _choice(
          label: 'Admission fee status',
          current: _draft.admissionFeeStatus,
          choices: const {
            'not_recorded': 'Not recorded / skip',
            'unpaid': 'Unpaid',
            'paid': 'Paid (verification required)',
          },
          onChanged: (v) => setState(() => _draft.admissionFeeStatus = v!),
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Uses school transport'),
          value: _draft.usesTransport,
          onChanged: (v) => setState(() => _draft.usesTransport = v),
        ),
        if (_draft.usesTransport) ...[
          TextFormField(
            initialValue: _draft.transportNotes,
            decoration: const InputDecoration(
              labelText: 'Transport notes',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _draft.transportNotes = v,
          ),
          const SizedBox(height: 12),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Request a fee discount'),
          subtitle: const Text('Requires an authorized discount rule later'),
          value: _draft.requestsDiscount,
          onChanged: (v) => setState(() => _draft.requestsDiscount = v),
        ),
        if (_draft.requestsDiscount)
          TextFormField(
            initialValue: _draft.discountNotes,
            decoration: const InputDecoration(
              labelText: 'Discount request notes',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _draft.discountNotes = v,
          ),
        const SizedBox(height: 12),
        const Text('Paid/unpaid is informational in this preview. '
            'No payment receipt or school ledger entry is created.'),
      ],
    );
  }

  Widget _reviewFields() {
    final warning = _draft.validateStep(AdmissionStep.review);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Review admission information',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        if (warning != null) ...[
          Text('Additional information required: $warning',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
        ],
        _summaryRow('Student', _draft.studentName),
        _summaryRow('Birth date', _dateLabel(_draft.dateOfBirth)),
        _summaryRow('Previous school',
            _draft.previousSchool.trim().isEmpty
                ? 'Not applicable'
                : _draft.previousSchool),
        _summaryRow('Guardians', _draft.guardians
            .map((g) => '${g.fullName} (${g.relationship}'
                '${g.isPrimary ? ', primary' : ''})')
            .join(', ')),
        _summaryRow('Campus', _campusChoices[_draft.campusId] ?? 'Not selected'),
        _summaryRow('Year', _yearChoices[_draft.academicYearId] ?? 'Not selected'),
        _summaryRow('Class', _classChoices[_draft.classId] ?? 'Not selected'),
        _summaryRow('Section', _sectionChoices[_draft.sectionId] ?? 'Unassigned'),
        _summaryRow('Document state', 'Conditional — awaiting verification'),
        _summaryRow('Document deadline', _dateLabel(_draft.missingDocumentsDueOn)),
        _summaryRow('Admission fee', _draft.admissionFeeStatus),
        _summaryRow('Transport', _draft.usesTransport ? 'Requested' : 'Not requested'),
        const SizedBox(height: 18),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('The application has NOT been saved or forwarded for '
                'approval. Academic placement choices may come from authorized '
                'DB01 records, but private document Storage and the audited '
                'DB02 admission endpoint are not connected. Submission remains disabled.'),
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 155,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
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
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final entry in choices.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: choices.isEmpty ? null : onChanged,
    );
  }

  Widget _actions() {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _step == 0 ? null : _previous,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Back'),
        ),
        const Spacer(),
        if (_step < AdmissionStep.values.length - 1)
          FilledButton.icon(
            key: const Key('wizard-next'),
            onPressed: _next,
            icon: const Icon(Icons.chevron_right),
            iconAlignment: IconAlignment.end,
            label: const Text('Next'),
          )
        else
          FilledButton.icon(
            key: const Key('wizard-submit-disabled'),
            onPressed: null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Submit unavailable'),
          ),
      ],
    );
  }
}
