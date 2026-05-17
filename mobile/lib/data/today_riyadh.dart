import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current calendar date in Asia/Riyadh (UTC+3 fixed), formatted as
/// yyyy-MM-dd. Matches the server-side `todayInResetTz()` helper used by
/// `incrementCount` to partition the daily leaderboard, so the client
/// queries the same subcollection key the server writes to.
///
/// Re-emits at every Riyadh midnight, so any provider that does
/// `ref.watch(todayRiyadhProvider)` automatically restarts its
/// downstream Firestore subscription as soon as the new challenge begins.
final todayRiyadhProvider = StreamProvider<String>((ref) async* {
  while (true) {
    yield _todayRiyadhDateString();
    final delay = _delayToNextRiyadhMidnight();
    // Guard against pathological clock skew; ensure we always wait at
    // least one second so a misbehaving system clock can't spin us.
    await Future<void>.delayed(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
    );
  }
});

String _todayRiyadhDateString() {
  final nowUtc = DateTime.now().toUtc();
  final riyadh = nowUtc.add(const Duration(hours: 3));
  final mm = riyadh.month.toString().padLeft(2, '0');
  final dd = riyadh.day.toString().padLeft(2, '0');
  return '${riyadh.year}-$mm-$dd';
}

Duration _delayToNextRiyadhMidnight() {
  final nowUtc = DateTime.now().toUtc();
  final riyadh = nowUtc.add(const Duration(hours: 3));
  final nextRiyadhMidnight =
      DateTime.utc(riyadh.year, riyadh.month, riyadh.day + 1);
  final nextResetUtc =
      nextRiyadhMidnight.subtract(const Duration(hours: 3));
  return nextResetUtc.difference(nowUtc);
}
