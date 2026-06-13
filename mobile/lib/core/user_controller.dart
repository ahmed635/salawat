import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/user_repository.dart';
import 'prefs.dart';

class UserNameController extends Notifier<String?> {
  @override
  String? build() => ref.read(prefsProvider).userName;

  Future<void> save(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    // Persist locally first so the UI can advance immediately even if the
    // network is slow.
    await ref.read(prefsProvider).setUserName(trimmed);
    state = trimmed;

    // Push the displayName to Firestore so the leaderboard shows it instead
    // of "Anonymous". Offline writes are queued by the SDK and replay later,
    // so the only failures that reach here are permission/App-Check errors —
    // swallow them so onboarding still completes; `_AuthGate`'s one-shot
    // resync retries on the next launch.
    try {
      await ref
          .read(userRepositoryProvider)
          .upsertProfile(displayName: trimmed);
    } catch (e) {
      debugPrint('upsertProfile failed during onboarding: $e');
    }
  }
}

final userNameControllerProvider =
    NotifierProvider<UserNameController, String?>(UserNameController.new);
