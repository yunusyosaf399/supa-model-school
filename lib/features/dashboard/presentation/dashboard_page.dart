import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/school_brand.dart';
import '../../auth/data/owner_auth_gateway.dart';
import '../data/dashboard_repository.dart';
import 'dashboard_visuals.dart';

/// Pixel-guided recreation of the approved desktop and Android dashboard.
/// It uses actual Flutter widgets (not a flattened screenshot) and retains
/// school-scoped, read-only data and explicit TEST DATA disclosure.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onNewAdmission,
    required this.onStudents,
    required this.onFees,
    required this.onAttendance,
    required this.onExpenses,
    this.onAdmissions,
    this.onSearch,
    this.onExit,
    this.onCampusChanged,
    this.owner,
    this.selectedCampusId,
    this.repository = const UnconfiguredDashboardRepository(),
  });

  final VoidCallback onNewAdmission;
  final VoidCallback onStudents;
  final VoidCallback onFees;
  final VoidCallback onAttendance;
  final VoidCallback onExpenses;
  final VoidCallback? onAdmissions;
  final VoidCallback? onSearch;
  final VoidCallback? onExit;
  final ValueChanged<String>? onCampusChanged;
  final OwnerAccess? owner;
  final String? selectedCampusId;
  final DashboardRepository repository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardSnapshot _data = DashboardSnapshot.preview();
  bool _loading = false;
  String? _error;
  int _loadSequence = 0;

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _deep => _dark ? const Color(0xFF6BDBD0) : DashboardColors.deep;
  Color get _text => _dark ? Colors.white : DashboardColors.ink;
  Color get _secondary =>
      _dark ? const Color(0xFFC2D4DA) : DashboardColors.muted;

  @override
  void initState() {
    super.initState();
    if (widget.owner != null) {
      // Do not briefly show demo numbers to an actual school account.
      _data = _emptySnapshot(widget.owner!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCampusId != widget.selectedCampusId ||
        oldWidget.owner?.userId != widget.owner?.userId ||
        oldWidget.repository != widget.repository) {
      if (widget.owner == null) {
        ++_loadSequence;
        _data = DashboardSnapshot.preview();
        _loading = false;
      } else {
        // Clear values from the previous campus before the new read.
        _data = _emptySnapshot(widget.owner!);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refresh();
        });
      }
    }
  }

  DashboardSnapshot _emptySnapshot(OwnerAccess owner) =>
      DashboardSnapshot.fromJson({
        'is_demo': false,
        'source': 'loading',
        'school_name': owner.schoolName,
        'campus_name': owner.campuses.isEmpty
            ? 'No campus'
            : owner.campuses.firstWhere(
                (c) => c.id == widget.selectedCampusId,
                orElse: () => owner.campuses.first,
              ).name,
        'year_label': owner.activeYearLabel ?? 'Not configured',
        'currency_code': owner.currencyCode,
        'fee_trend': <Object>[],
        'recent_admissions': <Object>[],
      });

  String? get _campusId {
    final owner = widget.owner;
    if (owner == null || owner.campuses.isEmpty) return null;
    if (owner.campuses.any((c) => c.id == widget.selectedCampusId)) {
      return widget.selectedCampusId;
    }
    return owner.campuses.first.id;
  }

  Future<void> _refresh() async {
    final owner = widget.owner;
    final campus = _campusId;
    if (owner == null || campus == null) {
      if (mounted) setState(() => _data = DashboardSnapshot.preview());
      return;
    }
    final request = ++_loadSequence;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.load(
        schoolId: owner.schoolId,
        campusId: campus,
      );
      if (!mounted || request != _loadSequence) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _loadSequence) return;
      setState(() {
        _data = _emptySnapshot(owner);
        _loading = false;
        _error = 'Dashboard data could not be loaded. '
            'Check the network and Owner access, then retry.';
      });
    }
  }

  String _count(num? amount) {
    if (amount == null) return '—';
    return amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }

  String _money(num? amount) {
    if (amount == null) return 'Not configured';
    final currency = _data.currencyCode;
    final prefix = switch (currency) {
      'PKR' => 'Rs',
      'NGN' => '₦',
      'GHS' => 'GH₵',
      'USD' => '\$',
      'SAR' => 'SAR',
      'XXX' => '',
      _ => currency,
    };
    return '$prefix ${_count(amount)}'.trim();
  }

  String _attendancePercent() {
    final present = _data.attendancePresent;
    final total = _data.attendanceTotal;
    if (present == null || total == null || total == 0) return '—';
    return '${(100 * present / total).toStringAsFixed(1)}%';
  }

  void _notAvailable(String item) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$item is not connected to live records yet.'),
      ));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final desktop = bounds.maxWidth >= 1010;
      final sidePadding = desktop ? 22.0 : 13.0;
      final contentWidth = math.max(0, bounds.maxWidth - 2 * sidePadding);
      return Stack(children: [
        Positioned.fill(child: ColoredBox(
          color: _dark ? const Color(0xFF10202A) : DashboardColors.background,
        )),
        const Positioned.fill(child: DashboardWaveBackground()),
        RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            key: const Key('dashboard-page'),
            padding: EdgeInsets.fromLTRB(
              sidePadding, desktop ? 15 : 0, sidePadding, desktop ? 16 : 22),
            children: [
              if (desktop) ...[
                _desktopToolbar(),
                const SizedBox(height: 22),
                _desktopTitleAndActions(),
              ] else
                _mobileWelcome(),
              if (_loading) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(key: Key('dashboard-loading')),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Material(
                  color: const Color(0xFFFFF5EA),
                  borderRadius: BorderRadius.circular(9),
                  child: ListTile(
                    leading: const Icon(Icons.error_outline, color: Colors.red),
                    title: Text(_error!, style: const TextStyle(fontSize: 12)),
                    trailing: TextButton(
                      onPressed: _refresh, child: const Text('Retry')),
                  ),
                ),
              ],
              const SizedBox(height: 15),
              _statGrid(contentWidth, desktop),
              if (!desktop) ...[
                const SizedBox(height: 12),
                _mobileActionGrid(contentWidth),
              ],
              const SizedBox(height: 15),
              if (desktop) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _admissionsPanel(desktop: true)),
                    const SizedBox(width: 15),
                    Expanded(flex: 7, child: _trendPanel()),
                  ],
                ),
                const SizedBox(height: 15),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _attendancePanel()),
                    const SizedBox(width: 15),
                    Expanded(child: _approvalsPanel(desktop: true)),
                    const SizedBox(width: 15),
                    Expanded(child: _syncPanel(desktop: true)),
                  ],
                ),
              ] else ...[
                _admissionsPanel(desktop: false),
                const SizedBox(height: 13),
                _approvalsPanel(desktop: false),
                const SizedBox(height: 13),
                _syncPanel(desktop: false),
                // On phones these secondary reports live below the primary
                // reference cards, rather than crowding the first screen.
                const SizedBox(height: 13),
                _trendPanel(),
                const SizedBox(height: 13),
                _attendancePanel(),
              ],
            ],
          ),
        ),
      ]);
    },
  );

  Widget _demoBadge() => Tooltip(
    message: 'TEST DATA: these figures are demonstrations, not school records.',
    child: Container(
      key: const Key('dashboard-demo-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0CC),
        border: Border.all(color: const Color(0xFFF2CF88)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.science_outlined, size: 15, color: Color(0xFF805508)),
        SizedBox(width: 4),
        Text('TEST DATA', style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w800,
          color: Color(0xFF805508),
        )),
      ]),
    ),
  );

  Widget _desktopToolbar() => SizedBox(
    height: 46,
    child: Row(children: [
      Expanded(
        flex: 4,
        child: OutlinedButton(
          key: const Key('open-global-search'),
          onPressed: widget.onSearch ?? () => _notAvailable('Global search'),
          style: OutlinedButton.styleFrom(
            backgroundColor: _dark ? const Color(0xFF18303A) : Colors.white,
            foregroundColor: _text,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            side: const BorderSide(color: Color(0xFFC4D4E0)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
          child: Row(children: [
            const Icon(Icons.search, size: 24),
            const SizedBox(width: 12),
            const Expanded(child: Text(
              'Search students, staff, invoices, etc...',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFE4ECF2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Ctrl + K', style: TextStyle(
                color: DashboardColors.ink, fontSize: 11)),
            ),
          ]),
        ),
      ),
      const SizedBox(width: 20),
      Container(width: 1, height: 32, color: const Color(0xFFB6C8D2)),
      const SizedBox(width: 20),
      _campusSelector(),
      const SizedBox(width: 12),
      _yearSelector(),
      const SizedBox(width: 16),
      _notificationButton(),
      const SizedBox(width: 12),
      Container(width: 1, height: 28, color: const Color(0xFFBBCDD5)),
      const SizedBox(width: 13),
      _accountButton(desktop: true),
    ]),
  );

  Widget _campusSelector({bool mobile = false}) {
    final campuses = widget.owner?.campuses ?? const <OwnerCampus>[];
    return PopupMenuButton<String>(
      key: const Key('owner-campus-selector'),
      enabled: campuses.length > 1,
      tooltip: 'Authorized campus',
      onSelected: widget.onCampusChanged,
      itemBuilder: (context) => [
        for (final c in campuses)
          PopupMenuItem<String>(value: c.id, child: Text(c.name)),
      ],
      child: Container(
        height: mobile ? 36 : 43,
        constraints: BoxConstraints(maxWidth: mobile ? 146 : 215),
        padding: EdgeInsets.symmetric(horizontal: mobile ? 9 : 12),
        decoration: BoxDecoration(
          color: _dark ? const Color(0xFF19323A) : Colors.white,
          borderRadius: BorderRadius.circular(mobile ? 23 : 10),
          border: Border.all(color: const Color(0xFFBDD0DB)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.location_city_outlined, size: mobile ? 17 : 21,
              color: _deep),
          const SizedBox(width: 7),
          Flexible(child: Text(_data.campusName,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _text, fontSize: mobile ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          )),
          const SizedBox(width: 7),
          Icon(Icons.keyboard_arrow_down_rounded,
              color: _text, size: mobile ? 17 : 20),
        ]),
      ),
    );
  }

  Widget _yearSelector() => Container(
    height: 43,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: _dark ? const Color(0xFF19323A) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFBDD0DB)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.calendar_month_outlined, size: 20, color: _deep),
      const SizedBox(width: 8),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 115),
        child: Text(_data.yearLabel,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: _text,
              fontWeight: FontWeight.w600)),
      ),
      const SizedBox(width: 8),
      Icon(Icons.keyboard_arrow_down_rounded, size: 19, color: _text),
    ]),
  );

  Widget _notificationButton() => IconButton.filledTonal(
    tooltip: 'Notifications (preview)',
    style: IconButton.styleFrom(
      backgroundColor: _dark ? const Color(0xFF1E3A41) : Colors.white,
      foregroundColor: _deep,
      fixedSize: const Size(42, 42),
    ),
    onPressed: () => _notAvailable('Notifications'),
    icon: Stack(clipBehavior: Clip.none, children: [
      const Icon(Icons.notifications_none_outlined, size: 25),
      if (_data.isDemo)
        Positioned(right: -7, top: -8, child: Container(
          width: 18, height: 18,
          decoration: const BoxDecoration(
              color: Color(0xFFDE2526), shape: BoxShape.circle),
          child: const Center(child: Text('3',
            style: TextStyle(color: Colors.white,
                fontSize: 10, fontWeight: FontWeight.w800))),
        )),
    ]),
  );

  Widget _accountButton({bool desktop = false}) => PopupMenuButton<String>(
    tooltip: 'Account',
    onSelected: (value) {
      if (value == 'exit') widget.onExit?.call();
    },
    itemBuilder: (context) => [
      PopupMenuItem<String>(
        value: 'exit',
        child: Text(widget.owner == null ? 'Exit demo' : 'Sign out'),
      ),
    ],
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: desktop ? 21 : 18,
        backgroundColor: const Color(0xFFB8E5DF),
        child: Icon(Icons.person, size: desktop ? 24 : 21,
            color: DashboardColors.deep),
      ),
      if (desktop) ...[
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 118),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.owner?.displayName ?? 'Demo Administrator',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: _text,
                    fontWeight: FontWeight.w800, fontSize: 12)),
              Text('Administrator', style: TextStyle(
                  color: _secondary, fontSize: 11)),
            ],
          ),
        ),
        Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _text),
      ],
    ]),
  );

  Widget _desktopTitleAndActions() => Row(
    children: [
      Container(width: 5, height: 57,
        decoration: BoxDecoration(
          color: DashboardColors.teal,
          borderRadius: BorderRadius.circular(6),
        )),
      const SizedBox(width: 16),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dashboard', style: TextStyle(
            fontSize: 35, height: 1, color: _deep,
            fontWeight: FontWeight.w900, letterSpacing: -1.2,
          )),
          const SizedBox(height: 6),
          Row(children: [
            Flexible(child: Text('${_data.campusName} • ${_data.yearLabel}',
              style: TextStyle(color: _secondary, fontSize: 14),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (_data.isDemo) ...[
              const SizedBox(width: 9),
              _demoBadge(),
            ],
          ]),
        ],
      )),
      const SizedBox(width: 8),
      _topAction('New Admission', Icons.person_add_alt_1_outlined,
          widget.onNewAdmission, primary: true),
      const SizedBox(width: 9),
      _topAction('Collect Fee', Icons.savings_outlined, widget.onFees),
      const SizedBox(width: 9),
      _topAction('Take Attendance', Icons.calendar_month_outlined,
          widget.onAttendance),
      const SizedBox(width: 9),
      _topAction('Record Expense', Icons.receipt_long_outlined,
          widget.onExpenses),
    ],
  );

  Widget _topAction(String label, IconData icon, VoidCallback onTap,
      {bool primary = false}) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return SizedBox(
      height: 46,
      child: primary
          ? FilledButton.icon(
              key: const Key('dashboard-new-admission'),
              style: FilledButton.styleFrom(
                backgroundColor: DashboardColors.deep,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                shape: shape,
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 20),
              label: Text(label, style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: _dark ? const Color(0xFF172C34) : Colors.white,
                foregroundColor: _deep,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: const BorderSide(color: Color(0xFFC4D4E1)),
                shape: shape,
              ),
              onPressed: onTap,
              icon: Icon(icon, size: 19),
              label: Text(label, style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _mobileWelcome() => Column(children: [
    Stack(children: [
      Positioned.fill(child: DashboardWaveBackground(mobile: true)),
      Padding(
        padding: const EdgeInsets.fromLTRB(7, 17, 7, 19),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SchoolMark(size: 47),
            const SizedBox(width: 6),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supa Model School', maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _deep, fontSize: 17,
                      fontWeight: FontWeight.w900, letterSpacing: -.35)),
                Text('School Management System', maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _secondary, fontSize: 10)),
              ],
            )),
            _notificationButton(),
            const SizedBox(width: 2),
            _accountButton(),
          ]),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight,
              child: _campusSelector(mobile: true)),
          const SizedBox(height: 17),
          Container(
            key: const Key('dashboard-mobile-greeting'),
            padding: const EdgeInsets.fromLTRB(11, 5, 5, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Good morning,', style: TextStyle(
                  fontSize: 29, fontWeight: FontWeight.w900,
                  letterSpacing: -.7, color: _deep,
                )),
                const SizedBox(height: 3),
                Text('Here is today’s summary.', style: TextStyle(
                  fontSize: 16, color: _secondary,
                )),
                const SizedBox(height: 12),
                Container(width: 43, height: 3,
                  decoration: BoxDecoration(
                    color: DashboardColors.teal,
                    borderRadius: BorderRadius.circular(4),
                  )),
                if (_data.isDemo) ...[
                  const SizedBox(height: 9),
                  _demoBadge(),
                ],
              ],
            ),
          ),
        ]),
      ),
    ]),
  ]);

  Widget _statGrid(double width, bool desktop) {
    final columns = desktop ? 4 : 2;
    final gap = desktop ? 15.0 : 10.0;
    final cardWidth = math.max(80.0, (width - gap * (columns - 1)) / columns);
    final height = desktop ? 119.0 : 110.0;
    return Wrap(spacing: gap, runSpacing: gap, children: [
      SizedBox(width: cardWidth, height: height,
        child: _metricCard(
          desktop: desktop,
          icon: Icons.groups_rounded,
          label: 'Active Students',
          value: _count(_data.activeStudents),
          color: DashboardColors.teal,
          badge: _data.isDemo ? (desktop ? '▲ +3.6%' : '↑ +12') : null,
          detail: desktop ? (_data.isDemo ? 'vs. last term' : 'Current campus') : null,
          badgeColor: const Color(0xFF16853B),
        ),
      ),
      SizedBox(width: cardWidth, height: height,
        child: _metricCard(
          desktop: desktop,
          icon: Icons.savings_outlined,
          label: 'Fee Collected',
          value: _money(_data.feeCollected),
          color: const Color(0xFF119D63),
          badge: _data.isDemo ? (desktop ? '▲ +12.4%' : '76%') : null,
          detail: desktop ? (_data.isDemo ? 'vs. last term' : null) : null,
          badgeColor: const Color(0xFF16853B),
        ),
      ),
      SizedBox(width: cardWidth, height: height,
        child: _metricCard(
          desktop: desktop,
          icon: Icons.warning_amber_rounded,
          label: 'Outstanding Fees',
          value: _money(_data.feesOutstanding),
          color: desktop ? DashboardColors.amber : DashboardColors.danger,
          badge: _data.isDemo ? (desktop ? '▲ +5.8%' : '24%') : null,
          detail: desktop ? (_data.isDemo ? 'vs. last term' : null) : null,
          badgeColor: DashboardColors.danger,
        ),
      ),
      SizedBox(width: cardWidth, height: height,
        child: _metricCard(
          desktop: desktop,
          icon: Icons.event_available_outlined,
          label: 'Today Attendance',
          value: desktop
              ? _attendancePercent()
              : (_data.attendancePresent == null ||
                      _data.attendanceTotal == null)
                  ? '—'
                  : '${_count(_data.attendancePresent)} / ${_count(_data.attendanceTotal)}',
          color: const Color(0xFF009D6B),
          badge: desktop ? null :
              _data.attendanceTotal == null ? null : _attendancePercent(),
          detail: desktop && _data.attendanceTotal != null
              ? '(${_count(_data.attendancePresent)} of ${_count(_data.attendanceTotal)})'
              : null,
          badgeColor: const Color(0xFF16853B),
        ),
      ),
    ]);
  }

  Widget _metricCard({
    required bool desktop,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color badgeColor,
    String? badge,
    String? detail,
  }) => DashboardPanel(
    padding: EdgeInsets.all(desktop ? 13 : 10),
    child: Row(children: [
      DashboardIconTile(
        icon: icon, color: color,
        background: color.withValues(alpha: .11),
        size: desktop ? 58 : 46,
      ),
      SizedBox(width: desktop ? 13 : 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _text, fontSize: desktop ? 13 : 11,
                fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          FittedBox(fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, maxLines: 1,
              style: TextStyle(color: _deep,
                fontWeight: FontWeight.w900,
                fontSize: desktop ? 27 : 19, letterSpacing: -.6)),
          ),
          if (desktop && (badge != null || detail != null)) ...[
            const SizedBox(height: 5),
            Row(children: [
              if (badge != null) Flexible(child: Text(badge,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: badgeColor,
                    fontSize: 11, fontWeight: FontWeight.bold))),
              if (detail != null) ...[
                const SizedBox(width: 3),
                Flexible(child: Text(detail,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _secondary, fontSize: 10))),
              ],
            ]),
          ] else if (!desktop && badge != null) ...[
            const SizedBox(height: 5),
            Align(alignment: Alignment.centerRight,
              child: _metricPill(badge, badgeColor)),
          ],
        ],
      )),
    ]),
  );

  Widget _metricPill(String value, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: fg.withValues(alpha: .11),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(value, style: TextStyle(
      color: fg, fontWeight: FontWeight.w800, fontSize: 11)),
  );

  Widget _mobileActionGrid(double width) {
    const gap = 8.0;
    final cell = (width - gap * 3) / 4;
    const actions = <(String, IconData)>[
      ('New\nAdmission', Icons.person_add_alt_1_outlined),
      ('Collect\nFee', Icons.savings_outlined),
      ('Attendance', Icons.event_available_outlined),
      ('Expenses', Icons.receipt_long_outlined),
    ];
    final callbacks = <VoidCallback>[
      widget.onNewAdmission,
      widget.onFees,
      widget.onAttendance,
      widget.onExpenses,
    ];
    return Row(children: [
      for (var i = 0; i < actions.length; i++) ...[
        SizedBox(width: cell, height: 99,
          child: DashboardPanel(
            padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(15),
              onTap: callbacks[i],
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(actions[i].$2,
                    size: 30, color: DashboardColors.teal),
                  const SizedBox(height: 7),
                  Text(actions[i].$1, textAlign: TextAlign.center,
                    maxLines: 2, style: TextStyle(
                      color: _text, fontSize: 11,
                      height: 1.05, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
        if (i != actions.length - 1) const SizedBox(width: gap),
      ],
    ]);
  }

  Widget _panelHeading(String title, IconData icon, {Widget? trailing}) =>
    Row(children: [
      Icon(icon, color: DashboardColors.teal, size: 25),
      const SizedBox(width: 9),
      Expanded(child: Text(title, maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _deep,
          fontWeight: FontWeight.w900, fontSize: 17))),
      if (trailing != null) trailing,
    ]);

  Widget _viewAll(VoidCallback? callback) => TextButton(
    onPressed: callback ?? () => _notAvailable('This list'),
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      foregroundColor: _deep,
      padding: const EdgeInsets.symmetric(horizontal: 1),
    ),
    child: const Row(mainAxisSize: MainAxisSize.min, children: [
      Text('View All', style: TextStyle(
        decoration: TextDecoration.underline,
        fontSize: 12, fontWeight: FontWeight.w600)),
      SizedBox(width: 3),
      Icon(Icons.arrow_forward_ios_rounded, size: 12),
    ]),
  );

  Widget _admissionsPanel({required bool desktop}) => DashboardPanel(
    key: const Key('dashboard-recent-admissions'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panelHeading('Recent Admissions', Icons.person_add_alt_1_outlined,
        trailing: _viewAll(widget.onStudents)),
      const SizedBox(height: 10),
      if (desktop)
        _recentTable()
      else
        _recentMobileList(),
    ]),
  );

  Widget _recentTable() => Column(children: [
    Container(
      height: 33,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1F5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(children: [
        Expanded(flex: 5, child: Text('Student Name',
            style: TextStyle(fontWeight: FontWeight.bold,
              fontSize: 11, color: DashboardColors.ink))),
        Expanded(flex: 3, child: Text('Class',
            style: TextStyle(fontWeight: FontWeight.bold,
              fontSize: 11, color: DashboardColors.ink))),
        Expanded(flex: 3, child: Text('Admission Date',
            style: TextStyle(fontWeight: FontWeight.bold,
              fontSize: 11, color: DashboardColors.ink))),
      ]),
    ),
    if (_data.recentAdmissions.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Text('No approved admissions in the active school year.'),
      ),
    for (final item in _data.recentAdmissions.take(4)) ...[
      SizedBox(height: 36, child: Row(children: [
        const CircleAvatar(radius: 12,
          backgroundColor: Color(0xFFE2EEEE),
          child: Icon(Icons.person, size: 15, color: DashboardColors.teal)),
        const SizedBox(width: 8),
        Expanded(flex: 5, child: Text(item.name, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _text, fontWeight: FontWeight.w600,
            fontSize: 11))),
        Expanded(flex: 3, child: Text(item.className, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _text, fontSize: 11))),
        Expanded(flex: 3, child: Text(item.when, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _text, fontSize: 11))),
      ])),
      const Divider(height: 1, color: Color(0xFFE1EAF0)),
    ],
  ]);

  Widget _recentMobileList() => Column(children: [
    if (_data.recentAdmissions.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Text('No approved admissions in the active school year.'),
      ),
    for (final entry in _data.recentAdmissions.take(3)) ...[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const DashboardIconTile(
            icon: Icons.school_outlined, size: 43),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: _text,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(entry.when, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: _secondary)),
            ],
          )),
          const SizedBox(width: 5),
          Container(
            constraints: const BoxConstraints(maxWidth: 75),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: DashboardColors.pale,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Text(entry.className, maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: DashboardColors.deep,
                fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
      const Divider(height: 1, color: Color(0xFFE1EAF0)),
    ],
  ]);

  Widget _trendPanel() => DashboardPanel(
    key: const Key('dashboard-fee-trend'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panelHeading('Fee Collection Trend', Icons.query_stats_outlined,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFFCDDAE4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Last 6 Months', style: TextStyle(
              color: _text, fontSize: 10)),
            const SizedBox(width: 5),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _text),
          ]),
        ),
      ),
      const SizedBox(height: 10),
      if (_data.feeTrend.isEmpty)
        const SizedBox(height: 180,
          child: Center(child: Text('Fee ledger has not been deployed.')))
      else LayoutBuilder(builder: (context, bounds) {
        final showSummary = bounds.maxWidth >= 480;
        return Row(children: [
          Expanded(child: DashboardTrendChart(
            months: _data.feeTrend,
            currency: _data.currencyCode,
            height: 190,
          )),
          if (showSummary) ...[
            const SizedBox(width: 13),
            SizedBox(width: 149, height: 185,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFECF6F2),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    const Icon(Icons.savings_outlined,
                        color: DashboardColors.deep, size: 25),
                    const Text('Total Collected',
                      style: TextStyle(fontSize: 11,
                          color: DashboardColors.ink)),
                    FittedBox(fit: BoxFit.scaleDown,
                      child: Text(_money(_data.feeCollected),
                        style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900,
                          color: DashboardColors.deep))),
                    const Divider(height: 8),
                    const Text('vs. Previous 6 Months',
                      style: TextStyle(fontSize: 10,
                          color: DashboardColors.ink)),
                    if (_data.isDemo)
                      const Align(alignment: Alignment.centerLeft,
                        child: Text('▲ +12.4%',
                          style: TextStyle(color: Color(0xFF15824C),
                              fontSize: 12, fontWeight: FontWeight.w800))),
                  ],
                ),
              ),
            ),
          ],
        ]);
      }),
    ]),
  );

  Widget _attendancePanel() {
    final p = _data.attendancePresent;
    final total = _data.attendanceTotal;
    final fraction = p == null || total == null || total <= 0
        ? 0.0 : (p / total).clamp(0.0, 1.0).toDouble();
    return DashboardPanel(
      key: const Key('dashboard-attendance-summary'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _panelHeading('Attendance Summary', Icons.calendar_month_outlined,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFC6D6E2)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Today', style: TextStyle(fontSize: 10)),
              Icon(Icons.keyboard_arrow_down_rounded, size: 15),
            ]),
          ),
        ),
        const Divider(height: 18, color: Color(0xFFDBE7EE)),
        if (total == null)
          const SizedBox(height: 142,
            child: Center(child: Text('Attendance records are not configured.')))
        else SizedBox(height: 142, child: Row(children: [
          DashboardDonutIndicator(ratio: fraction,
            label: _attendancePercent(), size: 126),
          const SizedBox(width: 10),
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _attendanceLine('Present', _count(p),
                DashboardColors.teal,
                extra: _attendancePercent()),
              const Divider(height: 16),
              _attendanceLine('Absent', _count(total - (p ?? 0)),
                const Color(0xFFB8CBD2),
                extra: '${(100 * (total - (p ?? 0)) / math.max(total, 1)).toStringAsFixed(1)}%'),
              const Divider(height: 16),
              _attendanceLine('Total Students', _count(total),
                DashboardColors.deep),
            ],
          )),
        ])),
      ]),
    );
  }

  Widget _attendanceLine(String label, String value, Color color,
      {String? extra}) => Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 6),
    Expanded(child: Text(label, maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 10, color: _text))),
    Text(value, style: TextStyle(fontSize: 11,
        fontWeight: FontWeight.w800, color: _text)),
    if (extra != null) ...[
      const SizedBox(width: 4),
      Text('($extra)', style: TextStyle(fontSize: 9, color: _secondary)),
    ],
  ]);

  Widget _approvalsPanel({required bool desktop}) => DashboardPanel(
    key: const Key('dashboard-pending-approvals'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panelHeading('Pending Approvals', Icons.fact_check_outlined,
        trailing: _viewAll(widget.onAdmissions)),
      const Divider(height: 16, color: Color(0xFFDBE7EE)),
      _approvalRow(desktop ? 'Admission Applications' : 'Admission Requests',
          Icons.person_add_alt_1_outlined,
          _data.pendingAdmissions, widget.onAdmissions ?? widget.onNewAdmission),
      _approvalRow('Expense Requests', Icons.receipt_long_outlined,
          _data.pendingExpenses, widget.onExpenses),
      _approvalRow(desktop ? 'Leave Requests' : 'Student Transfer Requests',
          desktop ? Icons.groups_2_outlined : Icons.swap_horiz_rounded,
          desktop ? _data.pendingLeave :
              _data.isDemo ? 1 : null,
          () => _notAvailable(desktop ? 'Leave Requests' : 'Student transfers')),
    ]),
  );

  Widget _approvalRow(String label, IconData icon, int? count,
      VoidCallback onTap) => Column(children: [
    InkWell(
      onTap: onTap,
      child: SizedBox(height: 45, child: Row(children: [
        Icon(icon, color: DashboardColors.teal, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _text))),
        Container(
          width: 42, height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBC6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(count == null ? '—' : '$count',
              style: const TextStyle(color: Color(0xFF8D5712),
                  fontSize: 12, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 12),
        Icon(Icons.chevron_right_rounded, size: 20, color: _secondary),
      ])),
    ),
    const Divider(height: 1, color: Color(0xFFE2E9ED)),
  ]);

  Widget _syncPanel({required bool desktop}) => DashboardPanel(
    key: const Key('dashboard-sync-status'),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _panelHeading(desktop ? 'Sync / Backup Status' : 'Sync Status',
        Icons.sync_outlined,
        trailing: desktop ? null : IconButton(
          tooltip: 'About synchronization',
          onPressed: () => _notAvailable('Device synchronization'),
          icon: Icon(Icons.info_outline_rounded,
            size: 20, color: _secondary),
        ),
      ),
      const SizedBox(height: 13),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFFE4F4EF),
        ),
        child: Row(children: [
          const Icon(Icons.cloud_off_outlined,
            color: DashboardColors.teal, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Not configured',
                style: TextStyle(color: DashboardColors.ink,
                    fontSize: 13, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Sync and backup services are not enabled.',
                maxLines: 2,
                style: TextStyle(color: DashboardColors.muted, fontSize: 10)),
            ],
          )),
          const Icon(Icons.storage_outlined,
              color: DashboardColors.teal, size: 28),
        ]),
      ),
      if (desktop) ...[
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _syncButton('Sync Now', Icons.sync_outlined)),
          const SizedBox(width: 9),
          Expanded(child: _syncButton('Backup Now', Icons.cloud_upload_outlined)),
        ]),
      ] else ...[
        const SizedBox(height: 9),
        Row(children: [
          const Icon(Icons.sync_rounded,
              color: DashboardColors.teal, size: 23),
          const SizedBox(width: 10),
          Expanded(child: Text(
            'Automatic synchronization will appear here once enabled.',
            style: TextStyle(fontSize: 11, color: _secondary),
          )),
        ]),
      ],
    ]),
  );

  Widget _syncButton(String label, IconData icon) => SizedBox(
    height: 34,
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: _dark ? const Color(0xFF19323A) : Colors.white,
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Color(0xFF0B978B)),
        foregroundColor: _deep,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () => _notAvailable(label),
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
    ),
  );
}