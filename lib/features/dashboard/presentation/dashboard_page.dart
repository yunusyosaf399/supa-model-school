import 'package:flutter/material.dart';

import '../../../ui/school_theme.dart';

/// Read-only dashboard design preview. Every count and amount below is
/// intentionally fictional. The app must not interpret it as an online result.
class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.onNewAdmission,
    required this.onStudents,
    required this.onFees,
    required this.onAttendance,
    required this.onExpenses,
  });

  final VoidCallback onNewAdmission;
  final VoidCallback onStudents;
  final VoidCallback onFees;
  final VoidCallback onAttendance;
  final VoidCallback onExpenses;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 880;
      final veryWide = constraints.maxWidth >= 1170;
      final pad = desktop ? 22.0 : 14.0;
      return ListView(
        key: const Key('dashboard-page'),
        padding: EdgeInsets.all(pad),
        children: [
          _header(context, desktop),
          const SizedBox(height: 16),
          _demoNotice(context),
          const SizedBox(height: 16),
          _stats(context, constraints.maxWidth - 2 * pad,
              desktop ? 4 : 2),
          const SizedBox(height: 18),
          _quickActions(context, constraints.maxWidth - 2 * pad,
              desktop ? 4 : 4),
          const SizedBox(height: 18),
          if (veryWide) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _recentAdmissions(context)),
              const SizedBox(width: 14),
              Expanded(child: _feeTrend(context)),
            ]),
          ] else ...[
            _recentAdmissions(context),
            const SizedBox(height: 14),
            _feeTrend(context),
          ],
          const SizedBox(height: 14),
          if (veryWide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: _attendance(context)),
              const SizedBox(width: 14),
              Expanded(child: _approvals(context)),
              const SizedBox(width: 14),
              Expanded(child: _sync(context)),
            ])
          else ...[
            _attendance(context),
            const SizedBox(height: 14),
            _approvals(context),
            const SizedBox(height: 14),
            _sync(context),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text('Supa Model School v1.0 • Preview data only',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      );
    });
  }

  Widget _header(BuildContext context, bool desktop) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(desktop ? 'Dashboard' : 'Good morning,',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            )),
        const SizedBox(height: 4),
        Text(desktop
            ? 'Sample Campus A • Academic Year 2026–2027'
            : 'Here is today\'s summary • Sample Campus A',
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
    if (!desktop) return title;
    return Row(children: [
      Expanded(child: title),
      const SizedBox(width: 10),
      FilledButton.icon(
        key: const Key('dashboard-new-admission'),
        onPressed: onNewAdmission,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('New Admission'),
      ),
    ]);
  }

  Widget _demoNotice(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Padding(
      padding: EdgeInsets.all(11),
      child: Row(children: [
        Icon(Icons.info_outline, size: 20),
        SizedBox(width: 10),
        Expanded(child: Text('DEMO PREVIEW — fictional figures and names. '
            'No fees, attendance, admissions, approvals or sync are loaded '
            'from Supabase yet.')),
      ]),
    ),
  );

  Widget _stats(BuildContext context, double width, int columns) {
    const gap = 12.0;
    final cellWidth = (width - gap * (columns - 1)) / columns;
    const items = <_Stat>[
      _Stat('Active Students', '1,248', '+3.6% sample',
          Icons.groups_rounded, Color(0xFF15A797)),
      _Stat('Fee Collected', 'PKR 4,860,750', '+12.4% sample',
          Icons.savings_outlined, Color(0xFF0E976D)),
      _Stat('Outstanding Fees', 'PKR 742,500', '+5.8% sample',
          Icons.warning_amber_rounded, Color(0xFFE19827)),
      _Stat('Today Attendance', '97.4%', '1,215 of 1,248 sample',
          Icons.event_available_outlined, Color(0xFF168A69)),
    ];
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final stat in items)
          SizedBox(width: cellWidth, child: _statCard(context, stat)),
      ],
    );
  }

  Widget _statCard(BuildContext context, _Stat stat) => Card(
    child: Padding(
      padding: const EdgeInsets.all(15),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(stat.icon, color: stat.color, size: 29),
        const SizedBox(height: 10),
        Text(stat.label, style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(stat.value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              )),
        ),
        const SizedBox(height: 5),
        Text(stat.hint, style: Theme.of(context).textTheme.labelSmall,
            maxLines: 2),
      ]),
    ),
  );

  Widget _quickActions(BuildContext context, double width, int columns) {
    const gap = 12.0;
    final w = (width - gap * (columns - 1)) / columns;
    final actions = <_Action>[
      _Action('New\nAdmission', Icons.person_add_alt_1_outlined, onNewAdmission),
      _Action('Collect\nFee', Icons.monetization_on_outlined, onFees),
      _Action('Take\nAttendance', Icons.event_available_outlined, onAttendance),
      _Action('Record\nExpense', Icons.receipt_long_outlined, onExpenses),
    ];
    return Wrap(spacing: gap, runSpacing: gap, children: [
      for (final action in actions)
        SizedBox(
          width: w,
          height: 100,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: action.onTap,
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(action.icon, color: Theme.of(context).colorScheme.primary,
                        size: 29),
                    const SizedBox(height: 7),
                    Text(action.label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _panel(BuildContext context, String title, IconData icon,
      Widget body, {Widget? trailing}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 9),
          Expanded(child: Text(title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800))),
          if (trailing != null) trailing,
        ]),
        const Divider(height: 24),
        body,
      ]),
    ),
  );

  Widget _recentAdmissions(BuildContext context) => _panel(
    context,
    'Recent Admissions',
    Icons.person_add_alt,
    Column(children: [
      _admission(context, 'Ayesha Khan', 'Grade 6 • Section A', 'Today'),
      _admission(context, 'Bilal Ahmed', 'Grade 4 • Section B', 'Today'),
      _admission(context, 'Sara Ali', 'Grade 2 • Section A', 'Yesterday'),
    ]),
    trailing: TextButton(onPressed: onStudents, child: const Text('View All')),
  );

  Widget _admission(BuildContext context, String name, String grade,
      String when) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: const Icon(Icons.school_outlined),
    ),
    title: Text(name),
    subtitle: Text('$grade • $when'),
  );

  Widget _feeTrend(BuildContext context) {
    const values = [0.38, 0.57, 0.75, 0.67, 0.82, 0.97];
    const months = ['Aug', 'Sep', 'Oct', 'Nov', 'Dec', 'Jan'];
    final primary = Theme.of(context).colorScheme.primary;
    return _panel(
      context,
      'Fee Collection Trend',
      Icons.bar_chart,
      SizedBox(
        height: 172,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < values.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Column(children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: values[i],
                          child: Container(
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: .8),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(months[i], style: Theme.of(context).textTheme.labelSmall),
                  ]),
                ),
              ),
          ],
        ),
      ),
      trailing: Text('Last 6 months',
          style: Theme.of(context).textTheme.labelSmall),
    );
  }

  Widget _attendance(BuildContext context) => _panel(
    context, 'Attendance Summary', Icons.calendar_month_outlined,
    Row(children: [
      SizedBox(
        width: 96,
        height: 96,
        child: Stack(alignment: Alignment.center, children: [
          const CircularProgressIndicator(
            value: .974, strokeWidth: 11,
            color: SchoolPalette.teal,
            backgroundColor: Color(0xFFDBE3E6),
            constraints: BoxConstraints(minWidth: 90, minHeight: 90),
          ),
          Text('97.4%', style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold)),
        ]),
      ),
      const SizedBox(width: 20),
      const Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Present: 1,215'),
          SizedBox(height: 9),
          Text('Absent: 33'),
          SizedBox(height: 9),
          Text('Total: 1,248'),
        ],
      )),
    ]),
  );

  Widget _approvals(BuildContext context) => _panel(
    context, 'Pending Approvals', Icons.assignment_turned_in_outlined,
    const Column(children: [
      _ApprovalRow('Admission Applications', 7),
      _ApprovalRow('Expense Requests', 4),
      _ApprovalRow('Leave Requests', 3),
    ]),
  );

  Widget _sync(BuildContext context) => _panel(
    context, 'Sync / Backup Status', Icons.sync_outlined,
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.cloud_off_outlined, color: Colors.orange),
        title: Text('Not connected'),
        subtitle: Text('No server synchronization or backup is active in '
            'the UI preview.'),
      ),
      OutlinedButton.icon(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
            'Sync is unavailable until device authorization, '
            'offline outbox and server tests are complete.',
          )),
        ),
        icon: const Icon(Icons.sync),
        label: const Text('Sync Now (preview)'),
      ),
    ]),
  );
}

class _Stat {
  const _Stat(this.label, this.value, this.hint, this.icon, this.color);
  final String label, value, hint;
  final IconData icon;
  final Color color;
}

class _Action {
  const _Action(this.label, this.icon, this.onTap);
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow(this.label, this.count);
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Chip(label: Text('$count')),
  );
}
