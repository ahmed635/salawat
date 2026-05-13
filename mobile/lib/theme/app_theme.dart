import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light({bool goldMode = false}) =>
      _build(Brightness.light, goldMode);
  static ThemeData dark({bool goldMode = false}) =>
      _build(Brightness.dark, goldMode);

  static ThemeData _build(Brightness brightness, bool goldMode) {
    final isDark = brightness == Brightness.dark;
    // When the daily community goal is reached, the brand swaps from
    // emerald/teal to an amber "gold" palette across the entire Material
    // theme (primary, secondary, nav indicator, etc.). Reverts at the next
    // UTC midnight reset.
    final primary = goldMode ? AppColors.amber500 : AppColors.emerald600;
    final secondary = goldMode ? AppColors.amber700 : AppColors.teal700;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: secondary,
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
            ? primary.withValues(alpha: 0.25)
            : primary.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.cairo(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? primary
                : (isDark ? AppColors.slate400 : AppColors.slate500),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected
                ? primary
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
  static LinearGradient headerGradient(
    Brightness brightness, {
    bool goldMode = false,
  }) {
    final isDark = brightness == Brightness.dark;
    if (goldMode) {
      return LinearGradient(
        begin: AlignmentDirectional.topEnd,
        end: AlignmentDirectional.bottomStart,
        colors: isDark
            ? const [AppColors.amber700, AppColors.amber900]
            : const [AppColors.amber500, AppColors.amber700],
      );
    }
    return LinearGradient(
      begin: AlignmentDirectional.topEnd,
      end: AlignmentDirectional.bottomStart,
      colors: isDark
          ? const [AppColors.emerald800, AppColors.teal900]
          : const [AppColors.emerald600, AppColors.teal700],
    );
  }
}
