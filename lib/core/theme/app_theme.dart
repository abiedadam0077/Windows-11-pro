import 'package:flutter/material.dart';

/// Brand palette: deep navy base, electric blue actions, violet accents.
/// Semantic colors: green = success, orange = warning/pending, red = error/stop.
abstract final class AppColors {
  static const background = Color(0xFF050B1E);
  static const surface = Color(0xFF0B1431);
  static const surfaceHigh = Color(0xFF131E47);
  static const cardStart = Color(0xFF1A2766);
  static const cardEnd = Color(0xFF0A1029);
  static const electricBlue = Color(0xFF2F80FF);
  static const violet = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF38BDF8);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
  static const textPrimary = Color(0xFFEAF0FF);
  static const textMuted = Color(0xFF9AA8CC);
  static const outline = Color(0xFF3B4D8F);

  static const lightBackground = Color(0xFFF2F5FF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightPrimary = Color(0xFF1F5EFF);
  static const lightSecondary = Color(0xFF6D3BE0);

  static const brandGradient = LinearGradient(
    colors: [electricBlue, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const cardGradient = LinearGradient(
    colors: [cardStart, cardEnd],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

abstract final class AppTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.electricBlue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.electricBlue,
      onPrimary: Colors.white,
      secondary: AppColors.violet,
      tertiary: AppColors.cyan,
      error: AppColors.danger,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.surfaceHigh,
      outline: AppColors.outline,
    );
    return _build(scheme, AppColors.background);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.lightPrimary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.lightPrimary,
      secondary: AppColors.lightSecondary,
      surface: AppColors.lightSurface,
      error: AppColors.danger,
    );
    return _build(scheme, AppColors.lightBackground);
  }

  static ThemeData _build(ColorScheme scheme, Color background) {
    final radius = BorderRadius.circular(16);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: RoundedRectangleBorder(borderRadius: radius),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.22),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 72,
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outline.withValues(alpha: 0.18),
        space: 1,
        thickness: 1,
      ),
    );
  }
}
