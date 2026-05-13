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

    // Await the Firestore write so displayName lands before any tap can
    // sync — otherwise the Cloud Function would stamp "Anonymous" into the
    // leaderboard. Offline writes are queued by the SDK and replay later.
    await ref.read(userRepositoryProvider).upsertProfile(displayName: trimmed);
  }
}

final userNameControllerProvider =
    NotifierProvider<UserNameController, String?>(UserNameController.new);
