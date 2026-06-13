import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs.dart';

/// Tracks whether the one-time how-to-use guide has been shown. `_AuthGate`
/// reads this to decide whether to insert the guide between name onboarding
/// and the main shell. State mirrors [Prefs.guideSeen].
class GuideController extends Notifier<bool> {
  @override
  bool build() => ref.read(prefsProvider).guideSeen;

  /// Mark the guide as seen so it never auto-shows again. Local-only; updates
  /// state synchronously then persists.
  Future<void> markSeen() async {
    if (state) return;
    state = true;
    await ref.read(prefsProvider).setGuideSeen(true);
  }
}

final guideControllerProvider =
    NotifierProvider<GuideController, bool>(GuideController.new);
