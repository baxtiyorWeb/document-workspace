import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final apiBaseUrlProvider = StateNotifierProvider<ApiBaseUrlNotifier, String>((
  ref,
) {
  return ApiBaseUrlNotifier();
});

class ApiBaseUrlNotifier extends StateNotifier<String> {
  static const _prefKey = 'custom_api_base_url';

  ApiBaseUrlNotifier() : super(_defaultBaseUrl) {
    _loadSavedUrl();
  }

  static String get _defaultBaseUrl {
    // http://localhost:8080 works for Web, Desktop, and physical Android devices via `adb reverse tcp:8080 tcp:8080`
    return 'http://localhost:8080';
  }

  Future<void> _loadSavedUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null && saved.trim().isNotEmpty) {
        state = saved.trim();
      }
    } catch (_) {}
  }

  Future<void> setBaseUrl(String newUrl) async {
    final trimmed = newUrl.trim();
    if (trimmed.isEmpty) return;
    state = trimmed;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, trimmed);
    } catch (_) {}
  }

  Future<void> resetToDefault() async {
    state = _defaultBaseUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (_) {}
  }
}
