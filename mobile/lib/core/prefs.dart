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
  static const _kLifetimeCount = 'sallou_lifetime_count';
  static const _kLastResetUtcDay = 'sallou_last_reset_utc_day';
  static const _kLifetimeBackfillTried = 'sallou_lifetime_backfill_tried';
  static const _kMilestoneFiredOnDay = 'sallou_milestone_fired_on_utc_day';
  static const _kCommittedDays = 'sallou_committed_days';
  static const _kLastActiveUtcDay = 'sallou_last_active_utc_day';

  final SharedPreferences _prefs;

  static Future<Prefs> load() async {
    final p = await SharedPreferences.getInstance();
    // Migration: prior to the daily-reset feature, [localCount] doubled as
    // the lifetime total (badges were unlocked from it). After the change,
    // localCount is daily and a separate [lifetimeCount] drives achievements.
    // Seed lifetimeCount from the existing localCount on first run after
    // upgrade so existing users keep their unlocked badges.
    if (!p.containsKey(_kLifetimeCount) && p.containsKey(_kLocalCount)) {
      await p.setInt(_kLifetimeCount, p.getInt(_kLocalCount) ?? 0);
    }
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

  /// Lifetime tap count since install. Independent of [localCount] (which
  /// resets every UTC midnight) — drives the profile/badges so achievements
  /// persist across days.
  int get lifetimeCount => _prefs.getInt(_kLifetimeCount) ?? 0;
  Future<void> setLifetimeCount(int value) =>
      _prefs.setInt(_kLifetimeCount, value);

  /// UTC date string (yyyy-MM-dd) of the most recent local daily reset.
  /// Null on a fresh install — first launch stamps today's date and starts
  /// the daily cycle.
  String? get lastResetUtcDay => _prefs.getString(_kLastResetUtcDay);
  Future<void> setLastResetUtcDay(String value) =>
      _prefs.setString(_kLastResetUtcDay, value);

  /// True once this device has attempted to call `backfillLifetimeShards`.
  /// The server is idempotent via its own marker doc; this flag just avoids
  /// a redundant call on every cold start.
  bool get lifetimeBackfillTried =>
      _prefs.getBool(_kLifetimeBackfillTried) ?? false;
  Future<void> setLifetimeBackfillTried(bool value) =>
      _prefs.setBool(_kLifetimeBackfillTried, value);

  /// UTC date (yyyy-MM-dd) on which we last fired the "2M challenge has
  /// begun" notification. Re-fires on the next UTC day so the user sees one
  /// celebration per cycle.
  String? get milestoneFiredOnUtcDay =>
      _prefs.getString(_kMilestoneFiredOnDay);
  Future<void> setMilestoneFiredOnUtcDay(String value) =>
      _prefs.setString(_kMilestoneFiredOnDay, value);

  /// Number of distinct UTC days on which the user has sent at least one
  /// salawat. Incremented client-side on the first tap of each new UTC day,
  /// so it works fully offline.
  int get committedDays => _prefs.getInt(_kCommittedDays) ?? 0;
  Future<void> setCommittedDays(int value) =>
      _prefs.setInt(_kCommittedDays, value);

  /// UTC date (yyyy-MM-dd) of the user's most recent tap. Used to detect
  /// the "first tap of a new day" transition that bumps [committedDays].
  String? get lastActiveUtcDay => _prefs.getString(_kLastActiveUtcDay);
  Future<void> setLastActiveUtcDay(String value) =>
      _prefs.setString(_kLastActiveUtcDay, value);
}

/// Overridden in main() with the loaded Prefs instance.
final prefsProvider = Provider<Prefs>((ref) {
  throw UnimplementedError('Override prefsProvider in main()');
});
