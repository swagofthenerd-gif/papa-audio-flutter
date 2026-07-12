import 'package:flutter/material.dart';

/// Papa Audio palette — carried over 1:1 from the React Native app so the new
/// Flutter build looks identical.
class PA {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF181818);
  static const surfaceElevated = Color(0xFF242424);
  static const card = Color(0xFF282828);
  static const accent = Color(0xFF1DB954);
  static const white = Color(0xFFFFFFFF);
  static const text = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB3B3B3);
  static const textMuted = Color(0xFF6A6A6A);
  static const separator = Color(0xFF282828);
  static const error = Color(0xFFE91429);
  static const warning = Color(0xFFF59B23);
}

ThemeData papaTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: PA.background,
    colorScheme: base.colorScheme.copyWith(
      primary: PA.accent,
      secondary: PA.accent,
      surface: PA.surface,
      error: PA.error,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: PA.text,
      displayColor: PA.text,
      fontFamily: 'Roboto',
    ),
    iconTheme: const IconThemeData(color: PA.textSecondary),
    splashColor: PA.accent.withOpacity(0.12),
    highlightColor: PA.accent.withOpacity(0.08),
  );
}
