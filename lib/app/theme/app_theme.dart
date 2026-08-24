import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const ColorScheme _lightColorScheme = ColorScheme.light(
    primary: Color(0xFF1E6F5C),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFD3F0E5),
    onPrimaryContainer: Color(0xFF00201A),
    secondary: Color(0xFF4A6572),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFCFE6F1),
    onSecondaryContainer: Color(0xFF0A1F28),
    tertiary: Color(0xFF7A5900),
    tertiaryContainer: Color(0xFFFFDEA3),
    error: Color(0xFFBA1A1A),
    surface: Color(0xFFF7FAF7),
    onSurface: Color(0xFF171D1B),
    surfaceContainerHighest: Color(0xFFDBE4E0),
  );

  static const ColorScheme _darkColorScheme = ColorScheme.dark(
    primary: Color(0xFF84D8BE),
    onPrimary: Color(0xFF00382C),
    primaryContainer: Color(0xFF005142),
    onPrimaryContainer: Color(0xFFA0F0DA),
    secondary: Color(0xFFB1CAD6),
    onSecondary: Color(0xFF1C343E),
    secondaryContainer: Color(0xFF334B55),
    onSecondaryContainer: Color(0xFFCCE6F2),
    tertiary: Color(0xFFF3BF3C),
    tertiaryContainer: Color(0xFF5C4300),
    error: Color(0xFFFFB4AB),
    surface: Color(0xFF101413),
    onSurface: Color(0xFFDFE4E1),
    surfaceContainerHighest: Color(0xFF3F4845),
  );

  static ThemeData get light => _buildTheme(_lightColorScheme);

  static ThemeData get dark => _buildTheme(_darkColorScheme);

  static ThemeData _buildTheme(ColorScheme scheme) {
    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    return base.copyWith(
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        indicatorColor: scheme.primaryContainer,
        height: 68,
      ),
    );
  }
}
