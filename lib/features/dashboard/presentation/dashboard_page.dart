import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../auth/data/owner_auth_gateway.dart';
import '../data/dashboard_repository.dart';
import '../../../ui/school_brand.dart';
import '../../../ui/school_theme.dart';

/// Responsive Windows / Android dashboard based on the supplied reference
/// screens. Only Owner-scoped summaries are loaded from Supabase; the separate
/// demo fixture is visibly labeled. Disabled modules never claim live data.
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
  static const _deep = Color(0xFF005957);
  static const _teal = Color(0xFF008E80);
  static const _pale = Color(0xFFE5F7F2);
  static const _ink = Color(0xFF142F37);
  DashboardSnapshot _data = DashboardSnapshot.preview();
  bool _loading = false;
  String? _error;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    // Never flash fictitious dashboard metrics as if they were account data.
    if (widget.owner != null) {
      _data = _emptyOwnerSnapshot(widget.owner!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.owner?.userId != oldWidget.owner?.userId ||
        widget.selectedCampusId != oldWidget.selectedCampusId ||
        widget.repository != oldWidget.repository) {
      if (widget.owner == null) {
        ++_version;
        _data = DashboardSnapshot.preview();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _refresh();
        });
      }
    }
  }

  DashboardSnapshot _emptyOwnerSnapshot(OwnerAccess owner) =>
      DashboardSnapshot.fromJson({
        'is_demo': false,
        'source': 'loading',
        'school_name': owner.schoolName,
        'campus_name': owner.campuses.isEmpty
            ? 'No campus' : owner.campuses.first.name,
        'year_label': owner.activeYearLabel ?? 'Not configured',
        'currency_code': owner.currencyCode,
        'fee_trend': [],
        'recent_admissions': [],
        'sync_status': 'Not configured',
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
      setState(() => _data = DashboardSnapshot.preview());
      return;
    }
    final request = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.repository.load(
        schoolId: owner.schoolId,
        campusId: campus,
      );
      if (!mounted || request != _version) return;
      setState(() {
        _data = result;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _version) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the school dashboard. '
            'Check your network and Owner access, then retry.';
        // Never show old campus numbers after a failed load.
        _data = DashboardSnapshot.fromJson({
          'is_demo': false,
          'school_name': owner.schoolName,
          'campus_name': owner.campuses.firstWhere(
            (c) => c.id == campus, orElse: () => owner.campuses.first,
          ).name,
          'year_label': owner.activeYearLabel ?? 'Not configured',
          'currency_code': owner.currencyCode,
          'source': 'unavailable',
          'fee_trend': [],
          'recent_admissions': [],
          'sync_status': 'Not configured',
        });
      });
    }
  }

  String _number(num? value) {
    if (value == null) return '—';
    final s = value.toStringAsFixed(0);
    return s.replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  }

  String _currency(num? value) =>
      value == null ? 'Not configured' :
      '${_data.currencyCode == 'XXX' ? '' : _data.currencyCode} ${_number(value)}'.trim();

  String _percent(int? present, int? total) {
    if (present == null || total == null || total == 0) return '—';
    return '${present * 100 / total >= 100 ? '100.0' : (present * 100 / total).toStringAsFixed(1)}%';
  }

  Color _surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF142D33) : Colors.white;

  Color _heading(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF73D8CB) : _deep;

  void _notConfigured(String module) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$module is not connected to live records yet.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, bounds) {
      final desktop = bounds.maxWidth >= 1060;
      final width = bounds.maxWidth;
      final pad = desktop ? 22.0 : 13.0;
      final contentsWidth = width - pad * 2;
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          key: const Key('dashboard-page'),
          padding: EdgeInsets.fromLTRB(pad, desktop ? 15 : 0, pad, 26),
          children: [
            if (desktop) ...[
              _desktopToolbar(),
              const SizedBox(height: 18),
              _desktopHeading(),
            ] else ...[
              _mobileHero(),
            ],
            if (_loading) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(key: Key('dashboard-loading')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  title: Text(_error!),
                  trailing: TextButton(
                    onPressed: _refresh, child: const Text('Retry')),
                ),
              ),
            ],
            if (_data.isDemo) ...[
              const SizedBox(height: 10),
              _demoNotice(),
            ] else if (!_loading) ...[
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
            _stats(contentsWidth, desktop),
            if (!desktop) ...[
              const SizedBox(height: 13),
              _quickActionTiles(contentsWidth),
            ],
            const SizedBox(height: 14),
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _recentAdmissions()),
                  const SizedBox(width: 14),
                  Expanded(flex: 7, child: _feeTrend()),
                ],
              )
            else ...[
              _recentAdmissions(),
              const SizedBox(height: 13),
            ],
            if (!desktop) ...[
              _approvals(),
              const SizedBox(height: 13),
              _sync(),
            ] else ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _attendance()),
                  const SizedBox(width: 14),
                  Expanded(child: _approvals()),
                  const SizedBox(width: 14),
                  Expanded(child: _sync()),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              _data.isDemo
                  ? 'TEST DASHBOARD • This is sample data, not actual student or payment activity.'
                  : 'Live summary • unavailable modules do not display fabricated data.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    });
  }

  Widget _demoNotice() => Container(
    key: const Key('dashboard-demo-banner'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4D9),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFFFE0A1)),
    ),
    child: Row(children: [
      const Icon(Icons.science_outlined, size: 19, color: Color(0xFF8B6100)),
      const SizedBox(width: 8),
      const Expanded(child: Text(
        'TEST DATA — Dashboard figures are still fictional previews. '
        'No real students, fees, attendance or approvals were created.',
        style: TextStyle(color: Color(0xFF714F00), fontSize: 12),
      )),
      TextButton(
        onPressed: _refresh,
        child: const Text('Refresh', style: TextStyle(fontSize: 12)),
      ),
    ]),
  );

  Widget _desktopToolbar() => Row(children: [
    Expanded(
      flex: 4,
      child: OutlinedButton.icon(
        key: const Key('open-global-search'),
        onPressed: widget.onSearch ??
            () => _notConfigured('Global search'),
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          backgroundColor: _surface(context),
          side: const BorderSide(color: Color(0xFFC3D4DA)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: const Icon(Icons.search, size: 22),
        label: const Text('Search students, staff, invoices, etc...   Ctrl + K',
            overflow: TextOverflow.ellipsis),
      ),
    ),
    const SizedBox(width: 18),
    _campusMenu(),
    const SizedBox(width: 12),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC3D4DA)),
      ),
      child: Row(children: [
        const Icon(Icons.calendar_month_outlined, size: 20, color: _deep),
        const SizedBox(width: 9),
        Text(_data.yearLabel, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 7),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
      ]),
    ),
    const SizedBox(width: 12),
    _notification(),
    const SizedBox(width: 7),
    _accountMenu(desktop: true),
  ]);

  Widget _campusMenu({bool compact = false}) {
    final owner = widget.owner;
    final campuses = owner?.campuses ?? const <OwnerCampus>[];
    return PopupMenuButton<String>(
      key: const Key('owner-campus-selector'),
      tooltip: 'Authorized campus',
      enabled: campuses.length > 1,
      onSelected: widget.onCampusChanged,
      itemBuilder: (context) => [
        for (final campus in campuses)
          PopupMenuItem(value: campus.id, child: Text(campus.name)),
      ],
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12, vertical: 11),
        decoration: BoxDecoration(
          color: _surface(context),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFC4D1D8)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_city_outlined, size: 20, color: _deep),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 110 : 154),
            child: Text(_data.campusName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        ]),
      ),
    );
  }

  Widget _notification() => IconButton(
    tooltip: 'Notifications (preview)',
    onPressed: () => _notConfigured('Notifications'),
    icon: const Badge(
      smallSize: 9,
      child: Icon(Icons.notifications_none_rounded, color: _deep, size: 26),
    ),
  );

  Widget _accountMenu({bool desktop = false}) => PopupMenuButton<String>(
    tooltip: 'Account',
    onSelected: (choice) {
      if (choice == 'exit') widget.onExit?.call();
    },
    itemBuilder: (_) => [
      PopupMenuItem<String>(
        value: 'exit',
        child: Text(widget.owner == null ? 'Exit demo' : 'Sign out'),
      ),
    ],
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      CircleAvatar(
        radius: desktop ? 19 : 18,
        backgroundColor: _pale,
        child: const Icon(Icons.person_rounded, color: _deep),
      ),
      if (desktop) ...[
        const SizedBox(width: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.owner?.displayName ?? 'Demo Administrator',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const Text('Administrator', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 17),
      ],
    ]),
  );

  Widget _desktopHeading() => Row(children: [
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 5, height: 43,
              decoration: BoxDecoration(color: _teal,
                  borderRadius: BorderRadius.circular(5))),
          const SizedBox(width: 15),
          Text('Dashboard',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: _heading(context), fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 3),
        Text('${_data.campusName} • ${_data.yearLabel}',
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    )),
    _headingAction('New Admission', Icons.person_add_alt_1_outlined,
        widget.onNewAdmission, primary: true),
    const SizedBox(width: 9),
    _headingAction('Collect Fee', Icons.savings_outlined, widget.onFees),
    const SizedBox(width: 9),
    _headingAction('Take Attendance', Icons.calendar_month_outlined,
        widget.onAttendance),
    const SizedBox(width: 9),
    _headingAction('Record Expense', Icons.receipt_long_outlined,
        widget.onExpenses),
  ]);

  Widget _headingAction(String label, IconData icon, VoidCallback tap,
      {bool primary = false}) =>
      SizedBox(height: 46, child: primary
        ? FilledButton.icon(
          key: const Key('dashboard-new-admission'),
          onPressed: tap,
          icon: Icon(icon, size: 19),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        )
        : OutlinedButton.icon(
          onPressed: tap,
          style: OutlinedButton.styleFrom(
            backgroundColor: _surface(context),
            foregroundColor: _heading(context),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label, style: const TextStyle(fontSize: 12)),
        ));

  Widget _mobileHero() => Column(children: [
    const SizedBox(height: 9),
    Row(children: [
      const SchoolMark(size: 52),
      const SizedBox(width: 6),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supa Model School',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900,
                color: _heading(context))),
          Text('School Management System',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ],
      )),
      _notification(),
      _accountMenu(),
    ]),
    const SizedBox(height: 9),
    Align(alignment: Alignment.centerRight, child: _campusMenu(compact: true)),
    const SizedBox(height: 9),
    // Compact text-only greeting: no decorative dashboard photography.
    Container(
      key: const Key('dashboard-mobile-greeting'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFE5F5F5), Color(0xFFF2F9FC)],
        ),
        border: Border.all(color: const Color(0xFFD6E8EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Good morning,',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: _heading(context),
            )),
          const SizedBox(height: 5),
          const Text('Here is today’s summary.',
            style: TextStyle(color: _ink, fontSize: 13)),
          const SizedBox(height: 10),
          Container(width: 53, height: 3, color: _teal),
        ],
      ),
    ),
  ]);

  Widget _stats(double availableWidth, bool desktop) {
    final columns = desktop ? 4 : 2;
    const gap = 11.0;
    final width = (availableWidth - (columns - 1) * gap) / columns;
    final children = [
      _stat('Active Students', _number(_data.activeStudents),
          Icons.groups_rounded, _teal, 'Current campus'),
      _stat('Fee Collected', _currency(_data.feeCollected),
          Icons.savings_outlined, const Color(0xFF13965E), 'Total collection'),
      _stat('Outstanding Fees', _currency(_data.feesOutstanding),
          Icons.warning_amber_rounded, const Color(0xFFD38921), 'Pending'),
      _stat('Today Attendance',
          _percent(_data.attendancePresent, _data.attendanceTotal),
          Icons.event_available_outlined, const Color(0xFF008D65),
          _data.attendanceTotal == null ? 'Not configured'
             : '${_number(_data.attendancePresent)} of ${_number(_data.attendanceTotal)}'),
    ];
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final child in children)
        SizedBox(width: width, height: desktop ? 122 : 108, child: child),
    ]);
  }

  Widget _stat(String label, String value, IconData icon, Color accent,
      String subtitle) => _card(
    padding: const EdgeInsets.all(13),
    child: Row(children: [
      Container(
        width: 48, height: 49,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, size: 28, color: accent),
      ),
      const SizedBox(width: 10),
      Expanded(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          FittedBox(fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
              style: TextStyle(
                fontSize: 23, fontWeight: FontWeight.w900,
                color: _heading(context),
              ))),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall),
        ],
      )),
    ]),
  );

  Widget _quickActionTiles(double availableWidth) {
    const gap = 9.0;
    final cell = (availableWidth - gap * 3) / 4;
    final actions = [
      ('New\nAdmission', Icons.person_add_alt_1_outlined, widget.onNewAdmission),
      ('Collect\nFee', Icons.savings_outlined, widget.onFees),
      ('Attendance', Icons.event_available_outlined, widget.onAttendance),
      ('Expenses', Icons.receipt_long_outlined, widget.onExpenses),
    ];
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (var i = 0; i < actions.length; i++)
        SizedBox(width: cell, height: 108,
          child: _card(padding: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: actions[i].$3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(actions[i].$2, size: 30, color: _teal),
                  const SizedBox(height: 9),
                  Text(actions[i].$1, textAlign: TextAlign.center,
                    maxLines: 2, style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, height: 1.05)),
                ],
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _card({required Widget child, EdgeInsetsGeometry? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: _surface(context),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFD7E6EB)),
        boxShadow: const [
          BoxShadow(color: Color(0x14046B72), blurRadius: 11, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(padding: padding ?? const EdgeInsets.all(14), child: child),
    );
  }

  Widget _panel(String heading, IconData icon, Widget child,
      {Widget? trailing}) => _card(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(icon, color: _teal, size: 24),
        const SizedBox(width: 9),
        Expanded(child: Text(heading, maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _heading(context), fontWeight: FontWeight.w900, fontSize: 18))),
        if (trailing != null) trailing,
      ]),
      const Divider(height: 17, color: Color(0xFFDDE8ED)),
      child,
    ]),
  );

  Widget _recentAdmissions() => _panel(
    'Recent Admissions',
    Icons.person_add_alt_1_outlined,
    Column(children: [
      if (_data.recentAdmissions.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Text('No approved admissions in the active school year.')),
      for (final entry in _data.recentAdmissions)
        Column(children: [
          Row(children: [
            CircleAvatar(
              radius: 16, backgroundColor: _pale,
              child: const Icon(Icons.school_outlined,
                  color: _teal, size: 19),
            ),
            const SizedBox(width: 9),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                Text(entry.when, style: Theme.of(context).textTheme.labelSmall),
              ],
            )),
            const SizedBox(width: 8),
            Flexible(child: Text(entry.className,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
          ]),
          const Divider(height: 18, color: Color(0xFFE2EAEF)),
        ]),
    ]),
    trailing: TextButton(
      onPressed: widget.onStudents,
      child: const Text('View All', style: TextStyle(
          decoration: TextDecoration.underline)),
    ),
  );

  Widget _feeTrend() => _panel(
    'Fee Collection Trend', Icons.trending_up_outlined,
    _data.feeTrend.isEmpty
      ? const SizedBox(
          height: 145,
          child: Center(child: Text('Fee ledger has not been deployed.')))
      : SizedBox(height: 170, child: LayoutBuilder(builder: (context, c) {
          final maxValue = _data.feeTrend
              .fold<num>(0, (maxSoFar, item) => math.max(maxSoFar, item.amount));
          return Stack(children: [
            Positioned.fill(child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 4; i++)
                  const Divider(height: 1, color: Color(0xFFE2ECEF)),
              ],
            )),
            Row(crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final month in _data.feeTrend)
                  Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(children: [
                      Expanded(child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: maxValue == 0 ? 0.01 :
                              (month.amount / maxValue).clamp(0.02, 1.0).toDouble(),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0xFF007B78), Color(0xFF66DCC5)],
                              ),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(5)),
                            ),
                          ),
                        ),
                      )),
                      const SizedBox(height: 8),
                      Text(month.label,
                        style: Theme.of(context).textTheme.labelSmall),
                    ]),
                  )),
              ],
            ),
          ]);
        })),
    trailing: Text('Last 6 Months', style: Theme.of(context).textTheme.labelSmall),
  );

  Widget _attendance() {
    final total = _data.attendanceTotal;
    final present = _data.attendancePresent;
    final proportion = total == null || total == 0 || present == null
        ? 0.0 : (present / total).clamp(0.0, 1.0).toDouble();
    return _panel(
      'Attendance Summary',
      Icons.calendar_month_outlined,
      total == null
        ? const SizedBox(height: 130,
          child: Center(child: Text('Attendance records are not configured.')))
        : Row(children: [
          SizedBox(
            height: 112, width: 112,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 100, height: 100,
                child: CircularProgressIndicator(
                  value: proportion, strokeWidth: 13,
                  strokeCap: StrokeCap.round, color: _teal,
                  backgroundColor: const Color(0xFFE1E9EC),
                ),
              ),
              Text(_percent(present,total),
                style: const TextStyle(fontWeight: FontWeight.w900,
                    color: _deep, fontSize: 18)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _countLine('Present', _number(present), _teal),
              const Divider(),
              _countLine('Absent', _number(total - (present ?? 0)),
                  const Color(0xFFB9C9D2)),
              const Divider(),
              _countLine('Total Students', _number(total), _deep),
            ],
          )),
        ]),
    );
  }

  Widget _countLine(String label, String value, Color color) => Row(children: [
    Container(width: 9, height: 9,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 7),
    Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
    Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
  ]);

  Widget _approvals() => _panel(
    'Pending Approvals', Icons.fact_check_outlined,
    Column(children: [
      _approvalRow('Admission Applications', Icons.school_outlined,
        _data.pendingAdmissions, widget.onAdmissions ?? widget.onNewAdmission),
      _approvalRow('Expense Requests', Icons.receipt_long_outlined,
        _data.pendingExpenses, widget.onExpenses),
      _approvalRow('Leave Requests', Icons.groups_2_outlined,
        _data.pendingLeave,
        () => _notConfigured('Leave requests')),
    ]),
    trailing: TextButton(
      onPressed: widget.onAdmissions ?? widget.onNewAdmission,
      child: const Text('View All', style: TextStyle(
          decoration: TextDecoration.underline)),
    ),
  );

  Widget _approvalRow(String label, IconData icon, int? count,
      VoidCallback navigate) => Column(children: [
    ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: _teal, size: 22),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBC5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(count == null ? '—' : '$count',
            style: const TextStyle(color: Color(0xFF8C5D14),
                fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, size: 18),
      ]),
      onTap: navigate,
    ),
    const Divider(height: 1, color: Color(0xFFE2EAEF)),
  ]);

  Widget _sync() => _panel(
    'Sync / Backup Status', Icons.sync_outlined,
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4F0),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Row(children: [
          Icon(Icons.cloud_off_outlined, color: _deep, size: 27),
          SizedBox(width: 8),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Not configured', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: _deep)),
              Text('Offline sync and backups will be enabled '
                   'after device authorization and testing.',
                  style: TextStyle(fontSize: 11, color: _ink)),
            ],
          )),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _notConfigured('Sync'),
          icon: const Icon(Icons.sync, size: 18),
          label: const Text('Sync Now', style: TextStyle(fontSize: 12)),
        )),
        const SizedBox(width: 7),
        Expanded(child: OutlinedButton.icon(
          onPressed: () => _notConfigured('Backup'),
          icon: const Icon(Icons.cloud_upload_outlined, size: 18),
          label: const Text('Backup Now', style: TextStyle(fontSize: 12)),
        )),
      ]),
    ]),
  );
}
