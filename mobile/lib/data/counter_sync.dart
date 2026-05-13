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
/// - Deltas larger than [_maxDeltaPerCall] (e.g. accumulated during a long
///   offline session) are split into sequential chunks. Each chunk gets its
///   own UUID and advances `lastSyncedCount` on success, so a failure
///   mid-loop preserves partial progress.
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

  // Must stay in sync with `MAX_DELTA_PER_CALL` in
  // functions/src/incrementCount.ts. Server rejects anything larger.
  static const _maxDeltaPerCall = 1000;

  final Ref ref;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final Prefs _prefs;

  Timer? _timer;
  Future<void>? _activeFlush;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_flushInterval, (_) => flushNow());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Force a flush — call from app lifecycle pause and on connectivity restore.
  ///
  /// Concurrent callers (periodic tick + lifecycle pause + daily reset) all
  /// share the same in-flight Future, so awaiting [flushNow] is guaranteed to
  /// wait for any active flush to finish. That's relied on by the daily
  /// reset, which zeros [Prefs.lastSyncedCount] right after — if it raced
  /// with an in-progress flush we could end up with localCount=0 but
  /// lastSyncedCount=N, permanently stalling future syncs.
  Future<void> flushNow() {
    final existing = _activeFlush;
    if (existing != null) return existing;
    if (_auth.currentUser == null) return Future.value();
    final future = _doFlush();
    _activeFlush = future;
    return future.whenComplete(() => _activeFlush = null);
  }

  Future<void> _doFlush() async {
    final localCount = ref.read(counterControllerProvider);
    var syncedSoFar = _prefs.lastSyncedCount;
    var remaining = localCount - syncedSoFar;
    if (remaining <= 0) return;

    try {
      while (remaining > 0) {
        final chunk = remaining > _maxDeltaPerCall ? _maxDeltaPerCall : remaining;

        // Reuse a persisted UUID across app restarts so a request that timed
        // out and retried after a kill still dedupes server-side. Each chunk
        // gets its own UUID, allocated lazily and cleared on success.
        final reqId = _prefs.pendingReqId ?? _uuid.v4();
        if (_prefs.pendingReqId == null) {
          await _prefs.setPendingReqId(reqId);
        }

        await _functions.httpsCallable('incrementCount').call({
          'delta': chunk,
          'clientRequestId': reqId,
          'clientTs': DateTime.now().toUtc().toIso8601String(),
        });

        // Persist the partial progress before the next chunk, so a crash or
        // network failure mid-loop leaves the counter in a consistent state.
        syncedSoFar += chunk;
        await _prefs.setLastSyncedCount(syncedSoFar);
        await _prefs.setPendingReqId(null);
        remaining -= chunk;
      }
    } catch (_) {
      // Keep pendingReqId + lastSyncedCount as-is so we retry next tick.
      // FirebaseFunctionsException details are intentionally swallowed; the
      // server's idempotency table handles double-deliveries.
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
