import 'package:flutter/material.dart';
import 'features/admissions/presentation/admission_wizard_page.dart';
import 'features/students/presentation/student_directory_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SupaModelSchoolApp());
}

class SupaModelSchoolApp extends StatelessWidget {
  const SupaModelSchoolApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Supa Model School',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b75)),
        ),
        home: const _SchoolShell(),
      );
}

class _SchoolShell extends StatefulWidget {
  const _SchoolShell();
  @override
  State<_SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends State<_SchoolShell> {
  int selected = 0;
  static const modules = <String>[
    'Dashboard', 'Students', 'Fees', 'Attendance', 'Employees',
    'Payroll', 'Expenses', 'Cashbook', 'Approvals', 'Reports',
    'Sync Center', 'Settings'
  ];

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 820;
    final content = selected == 1
        ? StudentDirectoryPage(
            onNewAdmission: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdmissionWizardPage(),
              ),
            ),
          )
        : Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    modules[selected],
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'UI scaffold only. Authentication, financial operations, '
                    'offline database and cloud sync are not yet implemented.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Supa Model School')),
      body: desktop
          ? Row(children: [
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: (v) => setState(() => selected = v),
                extended: MediaQuery.sizeOf(context).width >= 1150,
                scrollable: true,
                destinations: [
                  for (final m in modules)
                    NavigationRailDestination(
                        icon: const Icon(Icons.school_outlined), label: Text(m))
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content)
            ])
          : content,
      bottomNavigationBar: desktop ? null : NavigationBar(
        selectedIndex: selected < 4 ? selected : 4,
        onDestinationSelected: (v) {
          if (v < 4) {
            setState(() => selected = v);
          } else {
            showModalBottomSheet<void>(
              context: context,
              builder: (sheetContext) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
                  for (var i = 0; i < modules.length; i++)
                    ListTile(
                      title: Text(modules[i]),
                      onTap: () {
                        setState(() => selected = i);
                        Navigator.pop(sheetContext);
                      },
                    )
                ]),
              ),
            );
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.school_outlined), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.receipt_outlined), label: 'Fees'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Attend'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
