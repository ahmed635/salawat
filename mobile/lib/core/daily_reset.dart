import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/counter_sync.dart';
import 'counter_controller.dart';
import 'prefs.dart';

/// Resets the on-device "صلاة اليوم" counter to 0 at the start of each
/// **device-local** day. Per-user state runs on the user's own clock —
/// "today" feels like today regardless of where the user is — while the
/// shared global counter is reset by the server at Asia/Riyadh midnight
/// (a few hours apart for users outside that timezone). The lifetime
/// counter ([lifetimeCounterProvider]) is intentionally not touched so
/// achievements persist.
///
/// On reset we await any in-flight flush and then trigger one more, so
/// pending taps land on the *previous* day's daily leaderboard before the
/// local accumulator is zeroed.
class DailyResetController {
  DailyResetController({
    required this.ref,
    required FirebaseAuth auth,
    required Prefs prefs,
  })  : _auth = auth,
        _prefs = prefs;

  final Ref ref;
  final FirebaseAuth _auth;
  final Prefs _prefs;
  Timer? _timer;

  /// Runs an immediate check (in case the app launched on a new UTC day
  /// after sleeping across midnight) and arms a timer for the next 00:00 UTC.
  Future<void> start() async {
    await _checkAndReset();
    _scheduleNext();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkAndReset() async {
    final today = _todayLocal();
    final last = _prefs.lastResetUtcDay;
    if (last == today) return;

    // First launch — nothing to flush or reset. Just stamp today's date so
    // tomorrow's tick is a no-op until the day actually rolls.
    if (last == null) {
      await _prefs.setLastResetUtcDay(today);
      return;
    }

    // Flush whatever is pending so taps land on yesterday's leaderboard.
    // Best-effort: if we're offline this returns without writing the server,
    // and the un-flushed delta will be lost on the local reset. That's an
    // acceptable trade — we'd rather show an honest "0" for the new day than
    // keep yesterday's count visible indefinitely.
    if (_auth.currentUser != null) {
      await ref.read(counterSyncProvider).flushNow();
    }

    await ref.read(counterControllerProvider.notifier).reset();
    await _prefs.setLastSyncedCount(0);
    await _prefs.setPendingReqId(null);
    await _prefs.setLastResetUtcDay(today);
  }

  void _scheduleNext() {
    _timer?.cancel();
    final now = DateTime.now();
    // Local-time midnight tomorrow. DateTime(year, month, day) constructs
    // a local DateTime at 00:00:00, so this fires when the user's own
    // clock rolls into the next calendar day.
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    final delay = nextMidnight.difference(now);
    _timer = Timer(delay, () async {
      await _checkAndReset();
      _scheduleNext();
    });
  }

  static String _todayLocal() {
    final d = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

final dailyResetProvider = Provider<DailyResetController>((ref) {
  final controller = DailyResetController(
    ref: ref,
    auth: FirebaseAuth.instance,
    prefs: ref.read(prefsProvider),
  );
  ref.onDispose(controller.stop);
  return controller;
});
