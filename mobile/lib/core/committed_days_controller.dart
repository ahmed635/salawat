import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

/// Number of distinct **device-local** days on which the user has sent
/// at least one salawat. Bumped from [CounterController.tap] on the first
/// tap of each new local day. Purely local (Prefs-backed) so it works
/// offline and matches the user's own clock.
class CommittedDaysController extends Notifier<int> {
  @override
  int build() => ref.read(prefsProvider).committedDays;

  /// Called from the counter controller on every tap. No-op if the user
  /// has already tapped today (in their local timezone); otherwise +1 and
  /// stamp today.
  Future<void> recordActiveToday() async {
    final prefs = ref.read(prefsProvider);
    final today = _todayLocal();
    if (prefs.lastActiveUtcDay == today) return;
    final next = state + 1;
    state = next;
    await prefs.setCommittedDays(next);
    await prefs.setLastActiveUtcDay(today);
  }

  static String _todayLocal() {
    final d = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

final committedDaysProvider =
    NotifierProvider<CommittedDaysController, int>(
        CommittedDaysController.new);
