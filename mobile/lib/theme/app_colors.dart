import 'package:flutter/material.dart';

class AppColors {
  // Light theme
  static const Color lightPrimary = Color(0xFF2563EB);
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFF1F5F9);
  static const Color lightOnSurface = Color(0xFF0F172A);
  static const Color lightBorder = Color(0xFFE2E8F0);

  // Dark theme
  static const Color darkPrimary = Color(0xFF3B82F6);
  static const Color darkBackground = Color(0xFF0F172A);
  static const Color darkBackgroundDeep = Color(0xFF0D1117);
  static const Color darkSurface = Color(0xFF1E293B);
  static const Color darkOnSurface = Colors.white;
  static const Color darkBorder = Color(0xFF334155);

  // Text (legacy dark defaults — prefer theme helpers below)
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF94A3B8);

  // Accent
  static const Color accent = Color(0xFF3B82F6);

  // Semantic
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  /// Минимальный размер зоны нажатия (для работы в перчатках).
  static const double minTouchTarget = 44;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color scaffold(BuildContext context) =>
      isDark(context) ? darkBackground : lightBackground;

  static Color scaffoldDeep(BuildContext context) =>
      isDark(context) ? darkBackgroundDeep : lightSurface;

  static Color surface(BuildContext context) =>
      isDark(context) ? darkSurface : Colors.white;

  static Color border(BuildContext context) =>
      isDark(context) ? darkBorder : lightBorder;

  static Color onSurface(BuildContext context) =>
      isDark(context) ? darkOnSurface : lightOnSurface;

  static Color mutedText(BuildContext context) =>
      isDark(context) ? textSecondary : const Color(0xFF64748B);

  static Color primary(BuildContext context) =>
      isDark(context) ? darkPrimary : lightPrimary;
}
