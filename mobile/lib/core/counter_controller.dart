import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge.dart';
import 'committed_days_controller.dart';
import 'lifetime_counter_controller.dart';
import 'prefs.dart';

/// The "صلاة اليوم" counter — resets to 0 at every UTC midnight via
/// [DailyResetController]. Tapping also bumps the lifetime counter, and the
/// returned badge (if any) is keyed off the lifetime count so achievements
/// don't get re-unlocked every day.
class CounterController extends Notifier<int> {
  @override
  int build() => ref.read(prefsProvider).localCount;

  /// Increments by one, persists, returns the [Badge] unlocked by this tap
  /// against the *lifetime* count, if any (so the celebration UX only fires
  /// once per badge ever).
  Future<Badge?> tap() async {
    final next = state + 1;
    state = next;
    await ref.read(prefsProvider).setLocalCount(next);

    final beforeLifetime = ref.read(lifetimeCounterProvider);
    await ref.read(lifetimeCounterProvider.notifier).increment();
    // Detect the first tap of a new local day and bump the per-user
    // "committed days" counter (offline-safe, Prefs-backed).
    await ref.read(committedDaysProvider.notifier).recordActiveToday();
    final afterLifetime = ref.read(lifetimeCounterProvider);
    return badgeUnlockedAt(beforeLifetime, afterLifetime);
  }

  /// Folds in taps made outside the app (quick-tap notification, home-screen
  /// widget) and buffered natively while Flutter wasn't running.
  ///
  /// [today] are taps the buffer attributed to the current local day; they
  /// count toward "صلاة اليوم". [stale] are taps buffered before a local
  /// midnight the app has since passed — adding those to the daily counter
  /// would inflate a day they don't belong to, but they must still reach the
  /// lifetime total, because badges are permanent.
  ///
  /// Returns the badge crossed by the whole batch, if any. [badgeUnlockedAt]
  /// is documented as robust to non-incremental jumps, so a batch of 40 fires
  /// exactly the badge it crosses rather than none.
  Future<Badge?> addBackgroundTaps({
    required int today,
    required int stale,
  }) async {
    if (today <= 0 && stale <= 0) return null;

    if (today > 0) {
      final next = state + today;
      state = next;
      await ref.read(prefsProvider).setLocalCount(next);
    }

    final beforeLifetime = ref.read(lifetimeCounterProvider);
    await ref.read(lifetimeCounterProvider.notifier).addMany(today + stale);
    // Only a tap belonging to *today* makes today an active day.
    if (today > 0) {
      await ref.read(committedDaysProvider.notifier).recordActiveToday();
    }
    final afterLifetime = ref.read(lifetimeCounterProvider);
    return badgeUnlockedAt(beforeLifetime, afterLifetime);
  }

  /// Zero the daily counter. Called by [DailyResetController] at UTC midnight.
  Future<void> reset() async {
    state = 0;
    await ref.read(prefsProvider).setLocalCount(0);
  }
}

final counterControllerProvider =
    NotifierProvider<CounterController, int>(CounterController.new);
