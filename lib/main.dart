import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'features/auth/data/owner_auth_gateway.dart';

import 'features/admissions/presentation/admission_wizard_page.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/students/presentation/student_directory_page.dart';
import 'ui/school_brand.dart';
import 'ui/school_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only a public/publishable client key may be supplied to Flutter.
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  OwnerAuthGateway gateway = const UnconfiguredOwnerAuthGateway();
  if (url.isNotEmpty && key.isNotEmpty) {
    await Supabase.initialize(url: url, anonKey: key);
    gateway = SupabaseOwnerAuthGateway(Supabase.instance.client);
  }
  runApp(SupaModelSchoolApp(authGateway: gateway));
}

/// The normal startup shows Login. startInPreview is for isolated widget tests.
class SupaModelSchoolApp extends StatefulWidget {
  const SupaModelSchoolApp({
    super.key,
    this.startInPreview = false,
    this.authGateway,
  });
  final bool startInPreview;
  final OwnerAuthGateway? authGateway;

  @override
  State<SupaModelSchoolApp> createState() => _SupaModelSchoolAppState();
}

class _SupaModelSchoolAppState extends State<SupaModelSchoolApp> {
  ThemeMode themeMode = ThemeMode.system;
  bool? _preview;
  OwnerAccess? _authorized;
  bool _restoring = false;

  OwnerAuthGateway get _gateway =>
      widget.authGateway ?? const UnconfiguredOwnerAuthGateway();

  @override
  void initState() {
    super.initState();
    if (_gateway.configured && !widget.startInPreview) {
      _restoring = true;
      _restoreOwnerSession();
    }
  }

  Future<void> _restoreOwnerSession() async {
    OwnerAccess? authorized;
    try {
      authorized = await _gateway.restore();
    } catch (_) {
      // Invalid/revoked sessions never grant Owner access.
    }
    if (!mounted) return;
    setState(() {
      _authorized = authorized;
      _restoring = false;
    });
  }

  Future<void> _signIn(String email, String password) async {
    final authorized = await _gateway.signIn(email, password);
    if (!mounted) return;
    setState(() {
      _authorized = authorized;
      _preview = false;
    });
  }

  Future<void> _exitShell() async {
    if (_authorized != null) await _gateway.signOut();
    if (!mounted) return;
    setState(() {
      _authorized = null;
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
          : (_authorized != null || preview)
              ? _SchoolShell(
                  key: ValueKey(_authorized?.userId ?? 'debug-preview'),
                  owner: _authorized,
                  themeMode: themeMode,
                  onThemeChanged: (mode) => setState(() => themeMode = mode),
                  onExit: _exitShell,
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
    required this.themeMode,
    required this.onThemeChanged,
    required this.onExit,
    this.owner,
  });
  final OwnerAccess? owner;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback onExit;

  @override
  State<_SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends State<_SchoolShell> {
  int selected = 0;
  String? activeCampusId;

  static const modules = <String>[
    'Dashboard', 'Students', 'Admissions', 'Fees', 'Attendance',
    'Employees', 'Payroll', 'Expenses', 'Reports', 'Sync Center', 'Settings',
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
  ];

  void _newAdmission() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AdmissionWizardPage(),
    ));
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
      );
    }
    if (selected == 1) {
      return StudentDirectoryPage(onNewAdmission: _newAdmission);
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
      appBar: AppBar(
        titleSpacing: 14,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          if (desktop) ...[
            const SchoolMark(size: 35),
            const SizedBox(width: 8),
          ],
          const Flexible(child: Text('Supa Model School',
            overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          if (owner != null)
            PopupMenuButton<String>(
              key: const Key('owner-campus-selector'),
              tooltip: 'Authorized campus',
              icon: const Icon(Icons.location_city_outlined),
              onSelected: (id) => setState(() => activeCampusId = id),
              itemBuilder: (_) => [
                for (final campus in owner.campuses)
                  PopupMenuItem(value: campus.id, child: Text(campus.name)),
              ],
            ),
          IconButton(
            key: const Key('open-global-search'),
            tooltip: 'Global search',
            onPressed: _showGlobalSearch,
            icon: const Icon(Icons.search),
          ),
          _themeMenu(),
          IconButton(
            tooltip: 'Notifications (preview)',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(
                'Notifications are not connected to live data yet.',
              )),
            ),
            icon: const Icon(Icons.notifications_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Account',
            onSelected: (v) {
              if (v == 'exit') widget.onExit();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'exit',
                  child: Text(owner == null ? 'Exit demo' : 'Sign out')),
            ],
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Column(children: [
        if (owner != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Verified Owner: ${owner.displayName} • '
              '${owner.schoolName} • ${activeCampus?.name ?? 'No campus'}'
              '   |   Dashboard figures are still fictional previews.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(child: desktop
          ? Row(children: [
              NavigationRail(
                key: const Key('desktop-navigation'),
                selectedIndex: selected,
                onDestinationSelected: (i) => setState(() => selected = i),
                extended: extended,
                minExtendedWidth: 210,
                scrollable: true,
                backgroundColor: Theme.of(context).colorScheme.surface,
                destinations: [
                  for (var i = 0; i < modules.length; i++)
                    NavigationRailDestination(
                      icon: Icon(icons[i]),
                      selectedIcon: Icon(icons[i]),
                      label: Text(modules[i]),
                    ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ])
          : content),
      ]),
      bottomNavigationBar: desktop ? null : NavigationBar(
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
