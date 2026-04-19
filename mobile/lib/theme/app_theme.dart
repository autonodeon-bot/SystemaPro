import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Mobile 2026 theme — плотная типографика, мягкие радиусы, subtle borders.
/// Держим согласованность с web design-tokens: navy-blue base, crisp accent.
class AppTheme {
  // Дизайн-токены (mobile-зеркало design-tokens.css)
  static const double radiusXs = 8;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 18;

  static const double densityH = -1; // плотнее стандартного

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        visualDensity: const VisualDensity(horizontal: densityH, vertical: densityH),
        colorScheme: const ColorScheme.light(
          primary: AppColors.lightPrimary,
          onPrimary: Colors.white,
          surface: AppColors.lightBackground,
          onSurface: AppColors.lightOnSurface,
          secondary: AppColors.lightSurface,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.lightBackground,
        textTheme: _textTheme(AppColors.lightOnSurface),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.lightSurface,
          foregroundColor: AppColors.lightOnSurface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.lightOnSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.lightSurface,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: AppColors.lightBorder, width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusXs),
            borderSide: const BorderSide(color: AppColors.lightBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusXs),
            borderSide: const BorderSide(color: AppColors.lightPrimary, width: 1.6),
          ),
        ),
        chipTheme: const ChipThemeData(
          shape: StadiumBorder(side: BorderSide(color: AppColors.lightBorder)),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.lightBorder, space: 1, thickness: 1),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.lightPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.1),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: AppColors.lightBorder),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
          ),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        visualDensity: const VisualDensity(horizontal: densityH, vertical: densityH),
        colorScheme: const ColorScheme.dark(
          primary: AppColors.darkPrimary,
          onPrimary: Colors.white,
          surface: AppColors.darkBackground,
          onSurface: AppColors.darkOnSurface,
          secondary: AppColors.darkSurface,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        textTheme: _textTheme(AppColors.darkOnSurface),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.darkBackgroundDeep,
          foregroundColor: AppColors.darkOnSurface,
          elevation: 0,
          centerTitle: false,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
            color: AppColors.darkOnSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: -0.2,
          ),
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkSurface,
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
            side: const BorderSide(color: AppColors.darkBorder, width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusXs),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusXs),
            borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.6),
          ),
        ),
        chipTheme: const ChipThemeData(
          shape: StadiumBorder(side: BorderSide(color: AppColors.darkBorder)),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.darkBorder, space: 1, thickness: 1),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.1),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: AppColors.darkBorder),
            foregroundColor: AppColors.darkOnSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXs)),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkBackgroundDeep,
          selectedItemColor: AppColors.darkPrimary,
          unselectedItemColor: AppColors.textSecondary,
          selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
      );

  static TextTheme _textTheme(Color onSurface) {
    return TextTheme(
      displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.6),
      displayMedium: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.4),
      headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: onSurface, letterSpacing: -0.2),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface, letterSpacing: -0.1),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: onSurface),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: onSurface, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface, height: 1.4),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textSecondary, height: 1.35),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface),
      labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.4),
      labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary, letterSpacing: 0.6),
    );
  }
}
