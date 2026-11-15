import 'package:flutter/material.dart';
import 'ui/school_preview_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SupaModelSchoolApp());
}

/// The UI preview is intentionally separate from live school operations.
class SupaModelSchoolApp extends StatelessWidget {
  const SupaModelSchoolApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Supa Model School',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xff0b7269),
          ),
        ),
        home: const SchoolPreviewShell(),
      );
}
