import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

/// The user's **streak**: how many device-local days in a row they've sent at
/// least one salawat. Missing a full day drops it back to zero.
///
/// Stored as a pair — the streak length plus the day it was last extended —
/// rather than as a number something has to decrement. Nothing of ours runs
/// while the app is closed, so a plain stored count goes stale the moment the
/// user misses a day, and would need a catch-up pass on every launch to
/// correct. Deriving the displayed value from the stamp instead means a broken
/// streak reads as 0 the instant it's looked at, with nothing to schedule.
///
/// A consequence worth knowing: [Prefs.committedDays] on disk is the streak as
/// of [Prefs.lastActiveUtcDay], not as of today. It is never correct to show it
/// directly — go through [_streakAsOf].
///
/// Purely local (Prefs-backed) so it works offline and runs on the user's own
/// clock, same as the daily counter.
class CommittedDaysController extends Notifier<int> {
  @override
  int build() {
    final prefs = ref.read(prefsProvider);
    return _streakAsOf(
      stored: prefs.committedDays,
      lastActive: prefs.lastActiveUtcDay,
      today: todayLocal(),
    );
  }

  /// Called from the counter controller on every tap. No-op if the day is
  /// already counted; otherwise extends the streak, or starts a new one at 1
  /// if the chain was broken.
  ///
  /// Takes the day rather than assuming today because taps made from the
  /// floating bubble can be reconciled a day late — see
  /// [CounterController.addBackgroundTaps]. Those still earned the day they
  /// happened on.
  Future<void> recordActive(String day) async {
    final prefs = ref.read(prefsProvider);
    final last = prefs.lastActiveUtcDay;
    if (last == day) return;

    final target = _parseDay(day);
    if (target == null) return;
    final lastDate = _parseDay(last);
    // Never move the stamp backwards. A late-reconciled batch from before the
    // last recorded day can't retroactively rewrite the chain, and letting it
    // move the stamp would break the streak that has since been built on top.
    if (lastDate != null && !target.isAfter(lastDate)) return;

    final unbroken = lastDate != null && target.difference(lastDate).inDays == 1;
    final next = (unbroken ? prefs.committedDays : 0) + 1;

    await prefs.setCommittedDays(next);
    await prefs.setLastActiveUtcDay(day);
    // Not `next` — if this was a late-reconciled older day, the streak it
    // extends may already be dead as of today.
    state = _streakAsOf(stored: next, lastActive: day, today: todayLocal());
  }

  /// Re-evaluates against the current date. Needed only for an app left open
  /// across midnight, where nothing else would notice the day had rolled.
  void refresh() {
    final prefs = ref.read(prefsProvider);
    state = _streakAsOf(
      stored: prefs.committedDays,
      lastActive: prefs.lastActiveUtcDay,
      today: todayLocal(),
    );
  }

  /// The streak as it stands on [today], given a streak of [stored] that was
  /// last extended on [lastActive].
  ///
  /// A gap of one day is still alive: tapping yesterday and not yet today
  /// means the run is intact and today's tap will extend it. Two days apart
  /// means a whole day was missed, and the run is over.
  static int _streakAsOf({
    required int stored,
    required String? lastActive,
    required String today,
  }) {
    final last = _parseDay(lastActive);
    final now = _parseDay(today);
    if (last == null || now == null) return 0;
    final gap = now.difference(last).inDays;
    // gap < 0 means the device clock moved backwards; keep what they earned
    // rather than punishing them for a timezone flight.
    if (gap <= 1) return stored;
    return 0;
  }

  /// Parsed as UTC purely to get calendar arithmetic: differencing two local
  /// midnights lands on 23 or 25 hours across a DST boundary, which would
  /// silently miscount a day twice a year.
  static DateTime? _parseDay(String? day) {
    if (day == null) return null;
    final parts = day.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime.utc(y, m, d);
  }

  static String todayLocal() {
    final d = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

final committedDaysProvider =
    NotifierProvider<CommittedDaysController, int>(
        CommittedDaysController.new);
