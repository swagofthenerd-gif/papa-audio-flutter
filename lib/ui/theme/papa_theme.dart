import 'package:flutter/material.dart';

/// Papa Audio theming — Spotify-style dark with accent color system.
class PapaTheme {
  PapaTheme._();

  // Base colors
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF181818);
  static const Color surfaceElevated = Color(0xFF242424);
  static const Color card = Color(0xFF282828);

  // Accent system
  static Color _accentColor = const Color(0xFF1DB954); // Spotify green default
  static Color get accentColor => _accentColor;

  /// Change the accent color globally
  static void setAccentColor(Color color) {
    _accentColor = color;
  }

  /// Preset accent colors
  static const List<Color> presetAccents = [
    Color(0xFF1DB954), // Spotify Green
    Color(0xFFFF4757), // Red
    Color(0xFFFF6B35), // Orange
    Color(0xFFFFC107), // Amber
    Color(0xFF2ED573), // Lime
    Color(0xFF1E90FF), // Dodger Blue
    Color(0xFF7C4DFF), // Deep Purple
    Color(0xFFFF4081), // Pink
    Color(0xFF00BCD4), // Cyan
    Color(0xFFFF6D00), // Deep Orange
    Color(0xFF4CAF50), // Green
    Color(0xFF2196F3), // Blue
  ];

  // OLED pure-black mode
  static bool _isOledMode = false;
  static bool get isOledMode => _isOledMode;

  static void setOledMode(bool value) {
    _isOledMode = value;
  }

  /// Returns the appropriate background color based on OLED mode
  static Color getBackground() {
    return _isOledMode ? Colors.black : background;
  }

  static Color getSurface() {
    return _isOledMode ? const Color(0xFF080808) : surface;
  }

  static Color getSurfaceElevated() {
    return _isOledMode ? const Color(0xFF141414) : surfaceElevated;
  }

  static Color getCard() {
    return _isOledMode ? const Color(0xFF181818) : card;
  }

  // Text colors
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB3B3B3);
  static const Color textMuted = Color(0xFF6A6A6A);

  // Semantic
  static const Color error = Color(0xFFE91429);
  static const Color success = Color(0xFF1DB954);
  static const Color warning = Color(0xFFFFC107);

  /// Full ThemeData
  static ThemeData get themeData => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: getBackground(),
        colorScheme: ColorScheme.dark(
          primary: _accentColor,
          secondary: _accentColor,
          surface: getSurface(),
          error: error,
        ),
        cardColor: getCard(),
        dividerColor: const Color(0xFF333333),
        iconTheme: const IconThemeData(color: textSecondary),
        appBarTheme: AppBarTheme(
          backgroundColor: getBackground(),
          elevation: 0,
          foregroundColor: textPrimary,
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: getSurface(),
          selectedItemColor: _accentColor,
          unselectedItemColor: textSecondary,
          type: BottomNavigationBarType.fixed,
        ),
        tabBarTheme: TabBarTheme(
          labelColor: _accentColor,
          unselectedLabelColor: textSecondary,
          indicatorColor: _accentColor,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceElevated,
          contentTextStyle: const TextStyle(color: textPrimary),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        dialogTheme: DialogTheme(
          backgroundColor: surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: getSurface(),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),
        sliderTheme: SliderThemeData(
          activeColor: _accentColor,
          inactiveColor: const Color(0xFF535353),
          thumbColor: _accentColor,
          trackHeight: 3,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          ),
        ),
      );
}
