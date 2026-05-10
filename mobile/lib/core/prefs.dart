import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences with typed accessors for the keys
/// the app cares about. Keep all key strings in one place.
class Prefs {
  Prefs._(this._prefs);

  static const _kUserName = 'sallou_username';
  static const _kThemeMode = 'sallou_theme_mode';
  static const _kLocalCount = 'sallou_local_count';
  static const _kLastSyncedCount = 'sallou_last_synced_count';
  static const _kPendingReqId = 'sallou_pending_req_id';

  final SharedPreferences _prefs;

  static Future<Prefs> load() async {
    final p = await SharedPreferences.getInstance();
    return Prefs._(p);
  }

  String? get userName => _prefs.getString(_kUserName);
  Future<void> setUserName(String value) => _prefs.setString(_kUserName, value);

  ThemeMode get themeMode {
    switch (_prefs.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  int get localCount => _prefs.getInt(_kLocalCount) ?? 0;
  Future<void> setLocalCount(int value) => _prefs.setInt(_kLocalCount, value);

  /// The total count value the server has acknowledged. Difference between
  /// [localCount] and this is the pending delta to flush.
  int get lastSyncedCount => _prefs.getInt(_kLastSyncedCount) ?? 0;
  Future<void> setLastSyncedCount(int value) =>
      _prefs.setInt(_kLastSyncedCount, value);

  /// UUID of an in-flight incrementCount request, persisted so retries after
  /// app kill reuse the same idempotency key.
  String? get pendingReqId => _prefs.getString(_kPendingReqId);
  Future<void> setPendingReqId(String? value) async {
    if (value == null) {
      await _prefs.remove(_kPendingReqId);
    } else {
      await _prefs.setString(_kPendingReqId, value);
    }
  }
}

/// Overridden in main() with the loaded Prefs instance.
final prefsProvider = Provider<Prefs>((ref) {
  throw UnimplementedError('Override prefsProvider in main()');
});
