import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.emerald600,
      brightness: brightness,
      primary: AppColors.emerald600,
      secondary: AppColors.teal700,
      surface: isDark ? AppColors.slate900 : Colors.white,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? AppColors.slate950 : AppColors.slate50,
      brightness: brightness,
    );

    return base.copyWith(
      textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: (isDark ? AppColors.slate900 : Colors.white).withValues(alpha: 0.92),
        indicatorColor: isDark
            ? AppColors.emerald600.withValues(alpha: 0.25)
            : AppColors.emerald600.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? AppColors.emerald600
                : (isDark ? AppColors.slate400 : AppColors.slate500),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? AppColors.emerald600
                : (isDark ? AppColors.slate400 : AppColors.slate500),
          );
        }),
      ),
      cardTheme: CardTheme(
        color: isDark ? AppColors.slate800 : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  /// The header gradient used at the top of the main shell.
  static LinearGradient headerGradient(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return LinearGradient(
      begin: AlignmentDirectional.topEnd,
      end: AlignmentDirectional.bottomStart,
      colors: isDark
          ? const [AppColors.emerald800, AppColors.teal900]
          : const [AppColors.emerald600, AppColors.teal700],
    );
  }
}
