import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

/// Lifetime tap count since the app was installed. Separate from the daily
/// [counterControllerProvider] so badges/achievements survive the UTC
/// midnight reset.
class LifetimeCounterController extends Notifier<int> {
  @override
  int build() => ref.read(prefsProvider).lifetimeCount;

  Future<void> increment() async {
    final next = state + 1;
    state = next;
    await ref.read(prefsProvider).setLifetimeCount(next);
  }
}

final lifetimeCounterProvider =
    NotifierProvider<LifetimeCounterController, int>(
        LifetimeCounterController.new);
