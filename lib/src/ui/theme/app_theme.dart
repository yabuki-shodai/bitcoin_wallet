import 'package:flutter/material.dart';

class AppTheme {
  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF222222),
      onPrimary: Colors.white,
      secondary: Color(0xFF555555),
      surface: Color(0xFFEAF5FD),
      onSurface: Color(0xFF222222),
      onSurfaceVariant: Color(0xFF666666),
      outline: Color(0xFF9EB1BE),
      outlineVariant: Color(0xFFC7D6DE),
      surfaceTint: Colors.transparent,
    ),
    scaffoldBackgroundColor: const Color(0xFFEAF5FD),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFEAF5FD),
      foregroundColor: Color(0xFF222222),
      scrolledUnderElevation: 0,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: Color(0xFF222222),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFC7D6DE),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: false,
      backgroundColor: Color(0xFFEAF5FD),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(),
    ),
  );
}
