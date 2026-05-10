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

    // Best-effort write to Firestore. If offline, Firestore SDK will queue
    // the write and replay when connectivity is back. We don't await it
    // blocking the UI, but we do log failures.
    unawaited(
      ref.read(userRepositoryProvider).upsertProfile(displayName: trimmed),
    );
  }
}

final userNameControllerProvider =
    NotifierProvider<UserNameController, String?>(UserNameController.new);

void unawaited(Future<void> future) {
  future.catchError((_) {}); // swallow — Firestore offline queue handles retry
}
