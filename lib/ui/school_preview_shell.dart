import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/admissions/presentation/admission_wizard_page.dart';
import '../features/students/presentation/student_directory_page.dart';
import 'screen_catalog.dart';

/// Navigation and UI-only preview of the complete school screen inventory.
/// No authentication, file upload, storage, payment posting or sync occurs here.
class SchoolPreviewShell extends StatefulWidget {
  const SchoolPreviewShell({super.key});

  @override
  State<SchoolPreviewShell> createState() => _SchoolPreviewShellState();
}

class _SchoolPreviewShellState extends State<SchoolPreviewShell> {
  String module = 'Dashboard';
  int screenIndex = 0;
  String campus = 'Sample Campus A';
  String year = '2026–2027';
  String paymentMethod = 'Cash';
  String selectedFee = 'Tuition';
  final paymentController = TextEditingController(text: '1500');
  final cashCountController = TextEditingController(text: '57500');
  final Map<int, String> attendance = <int, String>{};
  final Map<String, bool> sampleSwitches = <String, bool>{};
  final Map<String, TextEditingController> draftFields =
      <String, TextEditingController>{};

  static const _students = <String>[
    'Demo Student A',
    'Demo Student B',
    'Demo Student C',
    'Demo Student D',
    'Demo Student E',
  ];
  static const _statuses = <String>['Present', 'Absent', 'Leave', 'Late'];

  @override
  void dispose() {
    paymentController.dispose();
    cashCountController.dispose();
    for (final controller in draftFields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void goTo(String nextModule, [int nextIndex = 0]) {
    setState(() {
      module = nextModule;
      screenIndex = nextIndex;
    });
  }

  void openAdmissionWizard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdmissionWizardPage(),
      ),
    );
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void showSearchDialog() {
    showSearch<void>(
      context: context,
      delegate: _SchoolScreenSearch(
        onChoose: (name, index) => goTo(name, index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 950;
    final reallyWide = MediaQuery.sizeOf(context).width >= 1360;
    final current = schoolScreenCatalog[module]![screenIndex];

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            showSearchDialog,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            () => goTo('Students'),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            () => goTo('Fees', 1),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xfff6f8fb),
          appBar: AppBar(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            titleSpacing: 16,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.school_rounded, color: Color(0xff0b7269)),
                const SizedBox(width: 9),
                const Flexible(
                  child: Text(
                    'Supa Model School',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
              ],
            ),
            actions: [
              if (reallyWide) _headerPill(Icons.calendar_today_outlined, year),
              if (reallyWide) const SizedBox(width: 8),
              if (wide)
                PopupMenuButton<String>(
                  tooltip: 'Choose a sample campus',
                  initialValue: campus,
                  onSelected: (v) => setState(() => campus = v),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'Sample Campus A', child: Text('Sample Campus A')),
                    PopupMenuItem(value: 'Sample Campus B', child: Text('Sample Campus B')),
                    PopupMenuItem(value: 'Sample Campus C', child: Text('Sample Campus C')),
                  ],
                  child: _headerPill(Icons.location_city_outlined, campus),
                ),
              IconButton(
                key: const Key('school-global-search'),
                tooltip: 'Search screens and actions (Ctrl+F)',
                icon: const Icon(Icons.search_rounded),
                onPressed: showSearchDialog,
              ),
              IconButton(
                tooltip: 'Prototype notification center',
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () => goTo('Dashboard', 2),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: CircleAvatar(
                  radius: 15,
                  backgroundColor: Color(0xffdcefeb),
                  child: Icon(Icons.person_outline, color: Color(0xff0b7269), size: 19),
                ),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide) ...[
                NavigationRail(
                  selectedIndex: schoolScreenCatalog.keys.toList().indexOf(module),
                  onDestinationSelected: (v) =>
                      goTo(schoolScreenCatalog.keys.elementAt(v)),
                  extended: reallyWide,
                  scrollable: true,
                  minExtendedWidth: 208,
                  backgroundColor: Colors.white,
                  indicatorColor: const Color(0xffdcefeb),
                  destinations: [
                    for (final name in schoolScreenCatalog.keys)
                      NavigationRailDestination(
                        icon: Icon(_moduleIcon(name)),
                        selectedIcon: Icon(_moduleIcon(name), color: const Color(0xff0b7269)),
                        label: Text(name),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPreviewNotice(),
                    _buildPageHeader(current),
                    _buildScreenTabs(),
                    Expanded(
                      child: module == 'Students' && screenIndex == 0
                          ? StudentDirectoryPage(
                              onNewAdmission: openAdmissionWizard,
                            )
                          : SingleChildScrollView(
                              key: ValueKey<String>(module + current.title),
                              padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
                              child: _buildScreen(current),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: const ['Dashboard', 'Students', 'Fees', 'Attendance']
                      .contains(module)
                      ? const ['Dashboard', 'Students', 'Fees', 'Attendance']
                          .indexOf(module)
                      : 4,
                  onDestinationSelected: (index) {
                    if (index == 4) {
                      _showMoreSheet();
                    } else {
                      goTo(const ['Dashboard', 'Students', 'Fees', 'Attendance'][index]);
                    }
                  },
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
                    NavigationDestination(icon: Icon(Icons.people_outline), label: 'Students'),
                    NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Fees'),
                    NavigationDestination(icon: Icon(Icons.fact_check_outlined), label: 'Attend'),
                    NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _headerPill(IconData icon, String title) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xfff4f7f8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 3),
            const Icon(Icons.keyboard_arrow_down, size: 16),
          ],
        ),
      );

  Widget _buildPreviewNotice() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: const Color(0xfffff4db),
        child: const Row(
          children: [
            Icon(Icons.construction_outlined, color: Color(0xff976a12), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'UI DESIGN PREVIEW • Fictional records only • No live login, payments, approvals or synchronization',
                style: TextStyle(color: Color(0xff76530c), fontSize: 11),
              ),
            ),
          ],
        ),
      );

  Widget _buildPageHeader(ScreenSpec spec) {
    final mobile = MediaQuery.sizeOf(context).width < 650;
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 14 : 24, 18, mobile ? 14 : 24, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(module,
                  style: const TextStyle(
                    letterSpacing: 1.7,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff687f8c),
                  )),
              const SizedBox(height: 3),
              Text(
                spec.title,
                style: TextStyle(
                  fontSize: mobile ? 20 : 26,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xff1c3341),
                ),
              ),
              if (spec.description.isNotEmpty)
                Text(spec.description,
                    style: const TextStyle(fontSize: 12, color: Color(0xff667b87))),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (module == 'Admissions' && screenIndex == 1)
                FilledButton.icon(
                  onPressed: openAdmissionWizard,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open existing wizard'),
                ),
              if (module == 'Students' && screenIndex == 0)
                OutlinedButton.icon(
                  onPressed: openAdmissionWizard,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                  label: const Text('New admission'),
                ),
              if (module != 'Students' || screenIndex != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: OutlinedButton.icon(
                    onPressed: () => showMessage(
                        'This is an interactive design preview. No school record was changed.'),
                    icon: const Icon(Icons.info_outline, size: 17),
                    label: const Text('Preview only'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScreenTabs() {
    final tabs = schoolScreenCatalog[module]!;
    return SizedBox(
      height: 51,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ChoiceChip(
          key: Key('screen-tab-' + i.toString()),
          label: Text(tabs[i].title, style: const TextStyle(fontSize: 12)),
          selected: i == screenIndex,
          onSelected: (_) => setState(() => screenIndex = i),
          selectedColor: const Color(0xffdcefeb),
          side: const BorderSide(color: Color(0xffdbe4e9)),
        ),
      ),
    );
  }

  Widget _buildScreen(ScreenSpec spec) {
    final heading = spec.later
        ? _notice('Planned later: this screen is not part of the 21-day operational pilot.')
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        if (spec.layout == PreviewLayout.overview) _overview(spec),
        if (spec.layout == PreviewLayout.table) _table(spec),
        if (spec.layout == PreviewLayout.form) _form(spec),
        if (spec.layout == PreviewLayout.payment) _payment(spec),
        if (spec.layout == PreviewLayout.attendance) _attendanceScreen(spec),
        if (spec.layout == PreviewLayout.closing) _cashClosing(),
        if (spec.layout == PreviewLayout.approvals) _approvalScreen(spec),
        if (spec.layout == PreviewLayout.sync) _syncScreen(spec),
        if (spec.layout == PreviewLayout.slip) _slip(spec),
        if (spec.layout == PreviewLayout.settings) _settings(spec),
        const SizedBox(height: 12),
        Text(
          'DESIGN STAGE · English-first · PKR · Preview values are illustrative',
          style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
        ),
      ],
    );
  }

  Widget _notice(String message) => Card(
        color: const Color(0xfffff7e7),
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            const Icon(Icons.info_outline, color: Color(0xff966c22)),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ]),
        ),
      );

  Widget _metric(String label, String value, IconData icon, String sub) => Container(
        width: 220,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: const Color(0xffe3e9ee)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: const Color(0xff0b7269), size: 22),
          const SizedBox(height: 17),
          Text(value, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(sub, style: const TextStyle(fontSize: 11, color: Color(0xff647985))),
        ]),
      );

  Widget _overview(ScreenSpec spec) {
    final finance = module == 'Finance' || module == 'Expenses' || module == 'Payroll';
    final metrics = finance
        ? [
            _metric('Money received', 'PKR 48,500', Icons.south_west, 'Demo this month'),
            _metric('Money paid', 'PKR 26,200', Icons.north_east, 'Demo this month'),
            _metric('Pending approval', '3', Icons.pending_actions, 'Sample requests'),
            _metric('Available cash', 'PKR 57,500', Icons.account_balance_wallet_outlined, 'Illustrative only'),
          ]
        : [
            _metric('Active students', '485', Icons.groups_2_outlined, 'Sample campus records'),
            _metric('Fee collected', 'PKR 148,500', Icons.payments_outlined, 'Sample this month'),
            _metric('Outstanding fees', 'PKR 32,400', Icons.receipt_long_outlined, 'Sample balances'),
            _metric('Today attendance', '92.6%', Icons.fact_check_outlined, 'Sample submitted registers'),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 12, runSpacing: 12, children: metrics),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final trends = _panel(
            'Monthly overview',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Illustrative collection trend', style: TextStyle(color: Color(0xff627786))),
              const SizedBox(height: 16),
              for (var i = 0; i < 6; i++) ...[
                Row(children: [
                  SizedBox(width: 32, child: Text(['Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov'][i],
                      style: const TextStyle(fontSize: 12))),
                  Expanded(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: [0.58, 0.76, 0.65, 0.88, 0.72, 0.93][i],
                      child: Container(
                        height: 11,
                        decoration: BoxDecoration(
                          color: const Color(0xff138578),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
              ],
            ]),
          );
          final tasks = _panel(
            'Quick actions',
            Column(children: [
              _quickAction('Collect student fee', Icons.payments_outlined, () => goTo('Fees', 1)),
              _quickAction('Take attendance', Icons.fact_check_outlined, () => goTo('Attendance')),
              _quickAction('Record an expense', Icons.receipt_outlined, () => goTo('Expenses', 1)),
              _quickAction('Daily cash closing', Icons.account_balance_wallet_outlined,
                  () => goTo('Finance', 2)),
            ]),
          );
          if (stacked) return Column(children: [trends, const SizedBox(height: 12), tasks]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: trends),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: tasks),
          ]);
        }),
      ],
    );
  }

  Widget _quickAction(String label, IconData icon, VoidCallback onTap) => ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: const Color(0xff0b7269)),
        title: Text(label),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: onTap,
      );

  Widget _panel(String title, Widget child) => Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );

  String _cellValue(String col, int i) {
    final name = col.toLowerCase();
    if (name.contains('student') || name.contains('employee') || name == 'name') {
      return name.contains('employee') ? 'Demo Employee ' + (i + 1).toString()
          : 'Demo Student ' + (i + 1).toString();
    }
    if (name.contains('status') || name.contains('approval')) {
      return ['Draft', 'Pending', 'Preview', 'Under review'][i % 4];
    }
    if (name.contains('date') || name.contains('when')) return '15 Nov 2026';
    if (name.contains('month') || name.contains('period')) return 'Nov 2026';
    if (name.contains('campus')) return campus;
    if (name.contains('class')) return 'Grade ' + (i + 2).toString() + '-A';
    if (name.contains('amount') || name.contains('paid') || name.contains('due') ||
        name.contains('balance') || name.contains('gross') ||
        name.contains('total') || name.contains('recovery') || name == 'cash' ||
        name == 'bank' || name == 'cost' || name.contains('tuition') ||
        name.contains('collected') || name.contains('salary')) {
      return 'PKR ' + [1200, 2400, 3150, 850][i % 4].toString();
    }
    if (name.contains('rate')) return '92%';
    if (name.contains('reference') || name.contains('receipt')) {
      return 'DEMO-' + (1001 + i).toString();
    }
    if (name.contains('role')) return 'Accountant';
    return 'Sample ' + (i + 1).toString();
  }

  Widget _table(ScreenSpec spec) {
    final columns = spec.columns.isEmpty
        ? const ['Reference', 'Name', 'Status']
        : spec.columns;
    return _panel(
      spec.title + ' · sample records',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 10, children: [
          SizedBox(
            width: 245,
            child: TextField(
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                labelText: 'Filter demo rows',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Chip(label: Text(campus)),
          const Chip(label: Text('5 fictional examples')),
        ]),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xffeff6f6)),
            columns: [
              for (final col in columns) DataColumn(label: Text(col)),
              const DataColumn(label: Text('Action')),
            ],
            rows: [
              for (var i = 0; i < 5; i++)
                DataRow(cells: [
                  for (final col in columns) DataCell(Text(_cellValue(col, i))),
                  DataCell(TextButton(
                    onPressed: () => _showDetailsDialog(spec.title, i),
                    child: const Text('View'),
                  )),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Text('Table layout, filters and record actions are UI previews; rows are not fetched from a database.',
            style: TextStyle(fontSize: 11, color: Color(0xff667b87))),
      ]),
    );
  }

  void _showDetailsDialog(String title, int i) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title + ' · sample detail'),
        content: Text('Fictional record ' + (i + 1).toString() +
            '. Actual details will load only after role/campus authorization is implemented.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _form(ScreenSpec spec) {
    final fields = spec.fields.isEmpty
        ? const ['Date', 'Reference', 'Amount', 'Description']
        : spec.fields;
    return _panel(
      'Draft form · ' + spec.title,
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Enter sample values to inspect form layout. Nothing is saved.',
            style: TextStyle(color: Color(0xff657b88))),
        const SizedBox(height: 16),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final field in fields)
              SizedBox(width: 285, child: _draftInput(spec.title, field)),
          ],
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: () {
            if (module == 'Admissions' && screenIndex == 1) {
              openAdmissionWizard();
            } else {
              showMessage('Demo values were not saved. Live validation and backend operations remain future work.');
            }
          },
          icon: const Icon(Icons.visibility_outlined),
          label: Text(module == 'Admissions' && screenIndex == 1
              ? 'Open actual Flutter wizard' : 'Review form preview'),
        ),
      ]),
    );
  }

  Widget _draftInput(String screen, String label) {
    final key = screen + '|' + label;
    final controller = draftFields.putIfAbsent(key, TextEditingController.new);
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: const Color(0xfffafbfd),
        isDense: true,
      ),
    );
  }

  Widget _payment(ScreenSpec spec) {
    final amount = double.tryParse(paymentController.text) ?? 0;
    const due = 3100.0;
    final allocated = math.max(0.0, math.min(due, amount));
    final remaining = due - allocated;
    final extra = math.max(0.0, amount - due);
    return _panel(
      spec.title + ' · calculation preview',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Selected record: Demo Student A · November 2026',
            style: TextStyle(color: Color(0xff657b88))),
        const SizedBox(height: 18),
        Wrap(spacing: 14, runSpacing: 14, children: [
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: selectedFee,
              decoration: const InputDecoration(
                labelText: 'Fee category',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Tuition', child: Text('Tuition')),
                DropdownMenuItem(value: 'Transport', child: Text('Transport')),
                DropdownMenuItem(value: 'Exam', child: Text('Exam')),
              ],
              onChanged: (v) => setState(() => selectedFee = v ?? selectedFee),
            ),
          ),
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              value: paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment method',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                DropdownMenuItem(value: 'Bank transfer', child: Text('Bank transfer')),
              ],
              onChanged: (v) => setState(() => paymentMethod = v ?? paymentMethod),
            ),
          ),
          SizedBox(
            width: 250,
            child: TextField(
              controller: paymentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Amount received (PKR)',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        Wrap(spacing: 12, runSpacing: 12, children: [
          _metric('Illustrative due', 'PKR 3,100', Icons.receipt_outlined, 'Month-wise charge'),
          _metric('Allocated', 'PKR ' + allocated.toStringAsFixed(2),
              Icons.check_circle_outline, 'Example allocation'),
          _metric('Remaining due', 'PKR ' + remaining.toStringAsFixed(2),
              Icons.pending_outlined, 'Amount still outstanding'),
          _metric('Unallocated advance', 'PKR ' + extra.toStringAsFixed(2),
              Icons.savings_outlined, 'Future credit in preview'),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: amount <= 0
              ? null
              : () => showMessage('Illustrative allocation calculated locally. No fee, salary or cash entry has been posted.'),
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Review calculation'),
        ),
      ]),
    );
  }

  Widget _attendanceScreen(ScreenSpec spec) {
    final marked = attendance.length;
    return _panel(
      spec.title + ' · current-date demo',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sample Campus A · Grade 5-A · 15 November 2026 · '
            + marked.toString() + ' / ' + _students.length.toString() + ' marked',
            style: const TextStyle(color: Color(0xff657b88))),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: marked / _students.length),
        const SizedBox(height: 12),
        for (var i = 0; i < _students.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(_students[i],
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                for (final status in _statuses)
                  ChoiceChip(
                    label: Text(status),
                    selected: attendance[i] == status,
                    onSelected: (_) => setState(() => attendance[i] = status),
                  ),
              ],
            ),
          ),
        const Divider(),
        Text('Present: ' + attendance.values.where((v) => v == 'Present').length.toString()
            + '   Absent: ' + attendance.values.where((v) => v == 'Absent').length.toString()
            + '   Leave: ' + attendance.values.where((v) => v == 'Leave').length.toString()
            + '   Late: ' + attendance.values.where((v) => v == 'Late').length.toString()),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: marked == _students.length
              ? () => showMessage('Register complete in preview only. No attendance was submitted.')
              : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Review completed register'),
        ),
        const SizedBox(height: 8),
        const Text('Leave is a non-attended day. Late counts as attended. Attendance Staff submits today only.',
            style: TextStyle(fontSize: 11, color: Color(0xff657b88))),
      ]),
    );
  }

  Widget _cashClosing() {
    const expected = 57500.0;
    final counted = double.tryParse(cashCountController.text);
    final difference = counted == null ? null : counted - expected;
    return _panel(
      'Daily Closing · Sample Campus A',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Daily closing is provisional while unsynced entries or unresolved conflicts remain.'),
        const SizedBox(height: 16),
        const Wrap(spacing: 12, runSpacing: 12, children: [
          _ClosingFact(label: 'Opening', amount: 'PKR 20,000'),
          _ClosingFact(label: 'Cash in', amount: 'PKR 55,000'),
          _ClosingFact(label: 'Cash out', amount: 'PKR 15,000'),
          _ClosingFact(label: 'Transfers out', amount: 'PKR 2,500'),
        ]),
        const SizedBox(height: 18),
        Text('Expected closing balance: PKR ' + expected.toStringAsFixed(2),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        const SizedBox(height: 12),
        SizedBox(
          width: 270,
          child: TextField(
            controller: cashCountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Physical cash counted (PKR)',
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          difference == null
              ? 'Enter a valid physical cash count.'
              : difference == 0
                  ? 'Cash agrees with the expected amount.'
                  : 'Discrepancy: PKR ' + difference.toStringAsFixed(2) +
                      ' — explanation and review required.',
          style: TextStyle(
            color: difference == 0 ? const Color(0xff0b7269) : const Color(0xffaa592c),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => showMessage('Cash close not finalized. Backend reconciliation is not connected.'),
          child: const Text('Review provisional closing'),
        ),
      ]),
    );
  }

  Widget _approvalScreen(ScreenSpec spec) {
    const actions = [
      ['Expense above threshold', 'PKR 8,500', 'Awaiting Owner'],
      ['Admission review', 'Demo Student C', 'Awaiting Principal'],
      ['Correction request', 'Receipt DEMO-101', 'Awaiting Owner'],
    ];
    return _panel(
      spec.title + ' · sample queue',
      Column(children: [
        for (final item in actions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const CircleAvatar(child: Icon(Icons.rule_folder_outlined)),
            title: Text(item[0]),
            subtitle: Text(item[1] + ' · ' + item[2]),
            trailing: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(item[0]),
                  content: const Text(
                    'Review should show original data, proposed changes, '
                    'reason, campus, approval policy and audit effect. '
                    'Only a verified online approver may finalize this action.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Close preview'),
                    ),
                  ],
                ),
              ),
              child: const Text('Review'),
            ),
          ),
        _notice('Approvals are visual examples only. Pending offline actions cannot be finalized locally.'),
      ]),
    );
  }

  Widget _syncScreen(ScreenSpec spec) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _metric('Pending uploads', '12', Icons.cloud_upload_outlined, 'Illustrative count'),
            _metric('Conflicts', '2', Icons.warning_amber_rounded, 'Unresolved examples'),
            _metric('Last successful sync', 'Not connected', Icons.sync, 'Runtime integration pending'),
          ]),
          const SizedBox(height: 16),
          _panel('Assigned campus offline model',
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Windows: assigned-campus SQLite cache. Android: online-only entry.'),
                const SizedBox(height: 10),
                const Text('Upload with idempotency → server validation → download authorized changes → conflict review.'),
                const SizedBox(height: 16),
                const Wrap(spacing: 10, runSpacing: 8, children: [
                  Chip(label: Text('Local draft')),
                  Chip(label: Text('Pending sync')),
                  Chip(label: Text('Pending approval')),
                  Chip(label: Text('Conflict')),
                  Chip(label: Text('Synced')),
                ]),
                const SizedBox(height: 16),
                const OutlinedButton.icon(
                  onPressed: null,
                  icon: Icon(Icons.sync),
                  label: Text('Sync Now · not connected'),
                ),
              ])),
        ],
      );

  Widget _slip(ScreenSpec spec) => Align(
        alignment: Alignment.topCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 530),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xffdce5ec)),
            boxShadow: const [BoxShadow(blurRadius: 16, color: Color(0x11000000))],
          ),
          child: Column(children: [
            const Icon(Icons.school_rounded, color: Color(0xff0b7269), size: 36),
            const SizedBox(height: 8),
            const Text('SUPA MODEL SCHOOL',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            Text(spec.title.toUpperCase(),
                style: const TextStyle(letterSpacing: 1.2, fontSize: 12)),
            const Divider(height: 32),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Reference: DEMO-001'), Text('Date: 15 Nov 2026')],
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Name: Demo Student A'), Text('Campus: Sample A')],
            ),
            const Divider(height: 30),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Illustrative description'), Text('PKR 2,000.00')],
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('Adjustment / discount'), Text('PKR -200.00')],
            ),
            const Divider(height: 30),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SAMPLE TOTAL', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('PKR 1,800.00', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 38),
            const Text('DEMO — NOT A VALID RECEIPT OR PAYMENT CONFIRMATION',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Color(0xffa04444))),
          ]),
        ),
      );

  Widget _settings(ScreenSpec spec) => _panel(
        spec.title + ' · configuration preview',
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Final authority and campus scope will be checked on the server.'),
          const SizedBox(height: 16),
          Wrap(spacing: 14, runSpacing: 14, children: [
            for (final field in spec.fields)
              SizedBox(
                width: 310,
                child: field.toLowerCase().contains('approval') ||
                        field.toLowerCase().contains('allow ') ||
                        field.toLowerCase().contains('auto ')
                    ? SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(field),
                        value: sampleSwitches[field] ?? false,
                        onChanged: (v) => setState(() => sampleSwitches[field] = v),
                      )
                    : _draftInput(spec.title, field),
              ),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showMessage('Settings are demonstration controls. No change has been saved.'),
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview settings'),
          ),
        ]),
      );

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (bottomContext) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: ListView(children: [
            const ListTile(
              title: Text('All modules', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Tap any module to open its screen designs.'),
            ),
            for (final name in schoolScreenCatalog.keys)
              ListTile(
                leading: Icon(_moduleIcon(name)),
                title: Text(name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(bottomContext);
                  goTo(name);
                },
              ),
          ]),
        ),
      ),
    );
  }

  IconData _moduleIcon(String name) {
    switch (name) {
      case 'Dashboard': return Icons.dashboard_outlined;
      case 'Students': return Icons.people_outline;
      case 'Admissions': return Icons.person_add_alt_outlined;
      case 'Fees': return Icons.receipt_long_outlined;
      case 'Attendance': return Icons.fact_check_outlined;
      case 'Employees': return Icons.badge_outlined;
      case 'Payroll': return Icons.account_balance_wallet_outlined;
      case 'Expenses': return Icons.shopping_bag_outlined;
      case 'Finance': return Icons.account_balance_outlined;
      case 'Canteen': return Icons.storefront_outlined;
      case 'Uniforms': return Icons.checkroom_outlined;
      case 'Vehicles': return Icons.directions_bus_outlined;
      case 'Approvals': return Icons.approval_outlined;
      case 'Reports': return Icons.bar_chart_outlined;
      case 'Sync Center': return Icons.sync_outlined;
      case 'Settings': return Icons.settings_outlined;
      case 'Search & Print': return Icons.print_outlined;
      case 'Authentication': return Icons.lock_outline;
      default: return Icons.school_outlined;
    }
  }
}

class _ClosingFact extends StatelessWidget {
  const _ClosingFact({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) => Container(
        width: 175,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xffdce5ec)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 7),
          Text(amount, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
      );
}

class _SchoolScreenSearch extends SearchDelegate<void> {
  _SchoolScreenSearch({required this.onChoose});

  final void Function(String module, int index) onChoose;

  @override
  String get searchFieldLabel => 'Search screens and actions';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        IconButton(icon: const Icon(Icons.clear),
            onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final matches = <(String, int, ScreenSpec)>[];
    for (final entry in schoolScreenCatalog.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final spec = entry.value[i];
        if (query.trim().isEmpty ||
            (entry.key + ' ' + spec.title + ' ' + spec.description)
                .toLowerCase().contains(query.toLowerCase())) {
          matches.add((entry.key, i, spec));
        }
      }
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, i) {
        final match = matches[i];
        return ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text(match.$3.title),
          subtitle: Text(match.$1),
          onTap: () {
            close(context, null);
            onChoose(match.$1, match.$2);
          },
        );
      },
    );
  }
}
