import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resilient storage service that uses secure storage with SharedPreferences fallback.
/// Prevents Android KeyStore crashes on specific phone manufacturers.
class StorageService {
  final FlutterSecureStorage _secureStorage;
  SharedPreferences? _prefs;
  bool _useFallback = false;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: false,
                resetOnError: true,
              ),
            );

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> write(String key, String value) async {
    if (!_useFallback) {
      try {
        await _secureStorage.write(key: key, value: value);
        return;
      } catch (e) {
        debugPrint('[WARN] SecureStorage write failed, falling back to SharedPreferences: $e');
        _useFallback = true;
      }
    }

    try {
      final prefs = await _getPrefs();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<String?> read(String key) async {
    if (!_useFallback) {
      try {
        final val = await _secureStorage.read(key: key);
        if (val != null) return val;
      } catch (e) {
        debugPrint('[WARN] SecureStorage read failed, falling back to SharedPreferences: $e');
        _useFallback = true;
      }
    }

    try {
      final prefs = await _getPrefs();
      return prefs.getString(key);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {}

    try {
      final prefs = await _getPrefs();
      await prefs.remove(key);
    } catch (_) {}
  }

  Future<void> deleteAll() async {
    try {
      await _secureStorage.deleteAll();
    } catch (_) {}

    try {
      final prefs = await _getPrefs();
      await prefs.remove('jwt_access_token');
      await prefs.remove('jwt_refresh_token');
      await prefs.remove('user_profile_json');
    } catch (_) {}
  }
}
