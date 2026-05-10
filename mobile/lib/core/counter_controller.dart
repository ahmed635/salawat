import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/badge.dart';
import 'prefs.dart';

class CounterController extends Notifier<int> {
  @override
  int build() => ref.read(prefsProvider).localCount;

  /// Increments by one, persists, returns the [Badge] unlocked by this tap
  /// if any (so callers can fire celebration UI / haptics).
  Future<Badge?> tap() async {
    final next = state + 1;
    state = next;
    await ref.read(prefsProvider).setLocalCount(next);
    return badgeUnlockedAt(next);
  }
}

final counterControllerProvider =
    NotifierProvider<CounterController, int>(CounterController.new);
