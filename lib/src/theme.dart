import 'package:flutter/material.dart';

/// Systematic text styles matching Spotify's hierarchy.
/// Every screen should reference these instead of defining inline styles.
class PapaText {
  PapaText._();

  // Display — for greeting headers
  static const display = TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PA.text, letterSpacing: -0.3);
  
  // Headline — section titles ("Recently played", "Your top tracks")
  static const headline = TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: PA.text, letterSpacing: -0.2);
  
  // Title — album names, track titles in lists
  static const title = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: PA.text, letterSpacing: -0.1);
  
  // Subtitle — artist names, album info
  static const subtitle = TextStyle(fontSize: 13, color: PA.textSecondary, letterSpacing: -0.05);
  
  // Body — normal text
  static const body = TextStyle(fontSize: 14, color: PA.text, height: 1.4);
  
  // Caption — metadata, durations, track counts
  static const caption = TextStyle(fontSize: 11, color: PA.textMuted, letterSpacing: 0.2);
  
  // Overline — "NOW PLAYING", section labels
  static const overline = TextStyle(fontSize: 11, color: PA.textSecondary, letterSpacing: 1.5, fontWeight: FontWeight.w600);
  
  // Button label
  static const button = TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.1);
  
  // Large title (for album detail screen)
  static const largeTitle = TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PA.text);
}

/// Papa Audio palette — carried over 1:1 from the React Native app so the new
/// Flutter build looks identical.
/// Short alias used throughout the app.
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

ThemeData papaTheme({bool oled = false}) {
  final bg = oled ? const Color(0xFF000000) : PA.background;
  final surf = oled ? const Color(0xFF0A0A0A) : PA.surface;
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,
    colorSchemeSeed: PA.accent,
    useMaterial3: true,
    fontFamily: 'Roboto',
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: const TextTheme(
      headlineLarge: PapaText.display,
      headlineMedium: PapaText.headline,
      titleLarge: PapaText.title,
      titleMedium: PapaText.subtitle,
      bodyLarge: PapaText.body,
      bodySmall: PapaText.caption,
      labelSmall: PapaText.overline,
      labelLarge: PapaText.button,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surf,
      indicatorColor: PA.accent.withValues(alpha: 0.2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surf,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PA.surfaceElevated,
      contentTextStyle: const TextStyle(color: PA.text),
      actionTextColor: PA.accent,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Legacy alias — some files reference `PapaColors` instead of `PA`.
typedef PapaColors = PA;
