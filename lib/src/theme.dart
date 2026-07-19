import 'package:flutter/material.dart';

/// Papa Audio palette — a Spotify-style dark system.
///
/// The three base surfaces are mutable so an AMOLED (pure-black) mode can swap
/// them at runtime. They have zero `const`-context uses, so this doesn't break
/// const widgets. Everything else stays `const`.
class PA {
  static Color background = _darkBg;
  static Color surface = _darkSurface;
  static Color surfaceElevated = _darkElevated;
  static const card = Color(0xFF282828);

  // Standard Spotify-dark greys.
  static const _darkBg = Color(0xFF121212);
  static const _darkSurface = Color(0xFF181818);
  static const _darkElevated = Color(0xFF242424);

  /// Pure-black surfaces for OLED screens (true black pixels are off = power
  /// saving, and the app looks deeper). Elevated stays a hair above black so
  /// sheets/menus still read as layered.
  static void applyAmoled(bool on) {
    background = on ? const Color(0xFF000000) : _darkBg;
    surface = on ? const Color(0xFF0A0A0A) : _darkSurface;
    surfaceElevated = on ? const Color(0xFF161616) : _darkElevated;
  }
  static const accent = Color(0xFF1DB954);
  static const white = Color(0xFFFFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  // Bumped from 0xFF6A6A6A: the old value sat ~3.4:1 on the background, under
  // WCAG AA for the small text (durations, timestamps) it's used on.
  static const textMuted = Color(0xFF8C8C8C);
  static const separator = Color(0xFF2A2A2A);
  static const error = Color(0xFFE91429);
  static const warning = Color(0xFFF59B23);

  // Corner-radius tokens so album art / cards / sheets stay consistent.
  static const rSm = 4.0;
  static const rMd = 8.0;
  static const rLg = 16.0;
}

ThemeData papaTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  // Seed a real M3 scheme from the brand green, then pin the surfaces to the
  // Papa greys. Without this the NavigationBar indicator falls back to M3's
  // default purple secondaryContainer — glaringly off-brand on a green app.
  final scheme = ColorScheme.fromSeed(
    seedColor: PA.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: PA.accent,
    secondary: PA.accent,
    surface: PA.surface,
    error: PA.error,
    secondaryContainer: const Color(0xFF16351F), // dark green indicator pill
    onSecondaryContainer: PA.accent,
  );
  return base.copyWith(
    scaffoldBackgroundColor: PA.background,
    colorScheme: scheme,
    textTheme: base.textTheme.apply(
      bodyColor: PA.text,
      displayColor: PA.text,
      fontFamily: 'Roboto',
    ),
    iconTheme: const IconThemeData(color: PA.textSecondary),
    splashColor: PA.accent.withValues(alpha: 0.12),
    highlightColor: PA.accent.withValues(alpha: 0.08),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PA.surface,
      indicatorColor: PA.accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PA.surfaceElevated,
      contentTextStyle: const TextStyle(color: PA.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
