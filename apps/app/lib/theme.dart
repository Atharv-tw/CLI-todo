import 'package:flutter/material.dart';

/// The palette: bold cards on near-black.
abstract final class AppColors {
  static const bg = Color(0xFF0E0E10);
  static const card = Color(0xFF1C1C1F);
  static const raised = Color(0xFF26262B);
  static const ink = Color(0xFFF4F1EA);
  static const muted = Color(0xFF8E8E93);
  static const line = Color(0xFF34343A);

  /// Tasks and primary actions.
  static const orange = Color(0xFFF2541B);

  /// Focus.
  static const lavender = Color(0xFF8E9BEF);

  /// Progress card; text on it uses [onLight].
  static const cream = Color(0xFFEDE6D6);

  /// "Now" and streak squares.
  static const green = Color(0xFF6FD943);
  static const red = Color(0xFFFF5A52);

  /// Text on the cream, lavender and green surfaces.
  static const onLight = Color(0xFF16161A);
}

const cardRadius = 24.0;

ThemeData appTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.orange, brightness: Brightness.dark).copyWith(
    primary: AppColors.orange,
    onPrimary: Colors.white,
    secondary: AppColors.lavender,
    onSecondary: AppColors.onLight,
    tertiary: AppColors.green,
    error: AppColors.red,
    surface: AppColors.bg,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.muted,
    outlineVariant: AppColors.line,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.raised,
    surfaceContainerHighest: AppColors.raised,
    secondaryContainer: AppColors.raised,
    onSecondaryContainer: AppColors.ink,
  );
  const pill = StadiumBorder();
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide.none,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(cardRadius)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(shape: pill)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: pill)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orange,
      foregroundColor: Colors.white,
      shape: pill,
    ),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide.none,
      backgroundColor: AppColors.raised,
      selectedColor: AppColors.orange,
      checkmarkColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.raised,
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.card),
    dialogTheme: const DialogThemeData(backgroundColor: AppColors.card),
    dividerTheme: const DividerThemeData(color: AppColors.line),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
