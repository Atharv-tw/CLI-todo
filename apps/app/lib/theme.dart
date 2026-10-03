import 'package:flutter/material.dart';

/// Same palette as the original HTML plan pages.
ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final ink = dark ? const Color(0xFFE6EFEE) : const Color(0xFF0F2C36);
  final paper = dark ? const Color(0xFF0C1F26) : const Color(0xFFF1F5F4);
  final card = dark ? const Color(0xFF112A33) : const Color(0xFFFFFFFF);
  final mist = dark ? const Color(0xFF183640) : const Color(0xFFDCE6E4);
  final tide = dark ? const Color(0xFF4CC2B0) : const Color(0xFF1D7F73);
  final buoy = dark ? const Color(0xFFFF8179) : const Color(0xFFC23B3B);
  final brass = dark ? const Color(0xFFE0B65A) : const Color(0xFF8A6A1E);
  final muted = dark ? const Color(0xFF9DB6BC) : const Color(0xFF4F6A72);
  final line = dark ? const Color(0xFF264852) : const Color(0xFFC9D7D4);

  final scheme = ColorScheme.fromSeed(seedColor: tide, brightness: brightness).copyWith(
    primary: tide,
    onPrimary: paper,
    secondary: brass,
    error: buoy,
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: muted,
    outline: muted,
    outlineVariant: line,
    surfaceContainerLowest: card,
    surfaceContainerLow: card,
    surfaceContainer: card,
    surfaceContainerHigh: mist,
    surfaceContainerHighest: mist,
    secondaryContainer: mist,
    onSecondaryContainer: ink,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    appBarTheme: AppBarTheme(backgroundColor: paper, surfaceTintColor: Colors.transparent),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: line),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}
