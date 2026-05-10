import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/counter_controller.dart';
import '../core/prefs.dart';

/// Owns the periodic flush of locally-buffered taps to the server.
///
/// Design (mirrors the React source's batching strategy):
/// - Local count increments instantly (already done by [CounterController]).
/// - Every [_flushInterval] OR when [flushNow] is called (e.g. app
///   backgrounded), if `localCount > lastSyncedCount` we call the
///   `incrementCount` Cloud Function with the delta + a UUID.
/// - On success, `lastSyncedCount` advances to the value at the time of the
///   request (captured *before* the call so taps during the request aren't
///   lost — they go in the next batch).
/// - On failure, state is preserved and we retry next tick using the same
///   UUID, so the server dedupes via its idempotency table.
class CounterSync {
  CounterSync({
    required this.ref,
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
    required Prefs prefs,
  })  : _functions = functions,
        _auth = auth,
        _prefs = prefs;

  static const _flushInterval = Duration(milliseconds: 2500);
  static const _uuid = Uuid();

  final Ref ref;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final Prefs _prefs;

  Timer? _timer;
  bool _flushing = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_flushInterval, (_) => flushNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Force a flush — call from app lifecycle pause and on connectivity restore.
  Future<void> flushNow() async {
    if (_flushing) return;
    if (_auth.currentUser == null) return;

    final localCount = ref.read(counterControllerProvider);
    final lastSynced = _prefs.lastSyncedCount;
    final delta = localCount - lastSynced;
    if (delta <= 0) return;

    _flushing = true;
    try {
      // Reuse a persisted UUID across app restarts so a request that timed
      // out and retried after a kill still dedupes server-side.
      final reqId = _prefs.pendingReqId ?? _uuid.v4();
      if (_prefs.pendingReqId == null) {
        await _prefs.setPendingReqId(reqId);
      }

      await _functions.httpsCallable('incrementCount').call({
        'delta': delta,
        'clientRequestId': reqId,
        'clientTs': DateTime.now().toUtc().toIso8601String(),
      });

      await _prefs.setLastSyncedCount(localCount);
      await _prefs.setPendingReqId(null);
    } catch (_) {
      // Keep pendingReqId + lastSyncedCount as-is so we retry next tick.
      // FirebaseFunctionsException details are intentionally swallowed; the
      // server's idempotency table handles double-deliveries.
    } finally {
      _flushing = false;
    }
  }
}

final counterSyncProvider = Provider<CounterSync>((ref) {
  final sync = CounterSync(
    ref: ref,
    functions: FirebaseFunctions.instance,
    auth: FirebaseAuth.instance,
    prefs: ref.read(prefsProvider),
  );
  ref.onDispose(sync.stop);
  return sync;
});
