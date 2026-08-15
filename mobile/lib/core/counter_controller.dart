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
    // Extend the day streak if this is the day's first tap (offline-safe,
    // Prefs-backed).
    await ref
        .read(committedDaysProvider.notifier)
        .recordActive(CommittedDaysController.todayLocal());
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
    String? staleDay,
  }) async {
    if (today <= 0 && stale <= 0) return null;

    if (today > 0) {
      final next = state + today;
      state = next;
      await ref.read(prefsProvider).setLocalCount(next);
    }

    final beforeLifetime = ref.read(lifetimeCounterProvider);
    await ref.read(lifetimeCounterProvider.notifier).addMany(today + stale);
    // Credit the day the taps actually happened on, not the day we happened to
    // reconcile them. Someone who only ever uses the floating bubble may not
    // open the app for days; without [staleDay] their streak would break over
    // days they did in fact send salawat on.
    final activeDay = today > 0 ? CommittedDaysController.todayLocal() : staleDay;
    if (activeDay != null) {
      await ref.read(committedDaysProvider.notifier).recordActive(activeDay);
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
