import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _prefKey = 'selected_theme_mode';

  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeString = prefs.getString(_prefKey);
      if (modeString == 'light') {
        state = ThemeMode.light;
      } else if (modeString == 'dark') {
        state = ThemeMode.dark;
      } else if (modeString == 'system') {
        state = ThemeMode.system;
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      String modeString = 'dark';
      if (mode == ThemeMode.light) modeString = 'light';
      if (mode == ThemeMode.system) modeString = 'system';
      await prefs.setString(_prefKey, modeString);
    } catch (_) {}
  }
}
