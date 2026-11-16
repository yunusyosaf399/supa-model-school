import 'package:flutter/material.dart';

/// One palette for the login, dashboards and existing feature modules.
abstract final class SchoolPalette {
  static const teal = Color(0xFF006B64);
  static const tealDark = Color(0xFF004E4B);
  static const mint = Color(0xFFE1F5F0);
  static const lightBackground = Color(0xFFF1F8FC);
  static const darkBackground = Color(0xFF0D1921);
}

abstract final class SchoolTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: SchoolPalette.teal,
      brightness: brightness,
      primary: dark ? const Color(0xFF5DDBCA) : SchoolPalette.teal,
      surface: dark ? const Color(0xFF162631) : Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? SchoolPalette.darkBackground
          : SchoolPalette.lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF10252B) : Colors.white,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: dark ? const Color(0xFF2D434A) : const Color(0xFFDDE8EA),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF20333C) : const Color(0xFFFBFDFD),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: dark
              ? const Color(0xFF148C80)
              : SchoolPalette.teal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: dark ? const Color(0xFF144F4A) : SchoolPalette.mint,
      ),
    );
  }
}
