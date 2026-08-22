import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages dark / light / system theme mode with local persistence.
///
/// Usage:
/// ```dart
/// // Read
/// final mode = context.watch<ThemeProvider>().mode;
///
/// // Toggle
/// context.read<ThemeProvider>().toggle();
/// ```
class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// Load the saved preference (call once at app startup).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    if (stored == 'dark') {
      _mode = ThemeMode.dark;
    } else if (stored == 'system') {
      _mode = ThemeMode.system;
    } else {
      _mode = ThemeMode.light;
    }
    notifyListeners();
  }

  /// Cycle: light → dark → system → light …
  void toggle() {
    switch (_mode) {
      case ThemeMode.light:
        _mode = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        _mode = ThemeMode.system;
        break;
      case ThemeMode.system:
        _mode = ThemeMode.light;
        break;
    }
    _save();
    notifyListeners();
  }

  /// Set to a specific mode.
  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    _save();
    notifyListeners();
  }

  void _save() async {
    final prefs = await SharedPreferences.getInstance();
    final label = switch (_mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_key, label);
  }

  // ---------------------------------------------------------------------------
  // Color tokens — the dark and light palettes live here so every widget can
  // access them through the provider instead of hardcoding hex values.
  // ---------------------------------------------------------------------------

  /// Surface background.
  Color get scaffoldBackground =>
      isDark ? const Color(0xFF1A1720) : const Color(0xFFFAF7F3);

  /// Card / sheet background.
  Color get cardBackground =>
      isDark ? const Color(0xFF242030) : Colors.white;

  /// Primary accent (coral).
  Color get accent => const Color(0xFFF4665C);

  /// Secondary accent (lavender).
  Color get secondary => const Color(0xFF9E86E6);

  /// Primary text.
  Color get textPrimary =>
      isDark ? const Color(0xFFF0EDF5) : const Color(0xFF2A2730);

  /// Secondary text.
  Color get textSecondary =>
      isDark ? const Color(0xFF9E99A7) : Colors.grey.shade600;

  /// Subtle border / divider.
  Color get divider =>
      isDark ? const Color(0xFF332F3E) : const Color(0x14000000);

  /// Success green.
  Color get success => const Color(0xFF3FBF7F);

  /// Error red.
  Color get error => const Color(0xFFB3261E);

  /// Icon tint on cards.
  Color get iconTint =>
      isDark ? const Color(0xFFB8B3C5) : Colors.grey.shade600;
}
