import 'dart:async';

import 'package:flutter/foundation.dart';
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
    yield riyadhDateStringAt(DateTime.now().toUtc());
    final delay = delayToNextRiyadhMidnightAt(DateTime.now().toUtc());
    // Guard against pathological clock skew; ensure we always wait at
    // least one second so a misbehaving system clock can't spin us.
    await Future<void>.delayed(
      delay > Duration.zero ? delay : const Duration(seconds: 1),
    );
  }
});

const _riyadhOffset = Duration(hours: 3); // UTC+3, fixed (no DST).

/// The Riyadh calendar date (yyyy-MM-dd) for a given UTC instant. Pure +
/// clock-injectable so the timezone math is unit-testable.
@visibleForTesting
String riyadhDateStringAt(DateTime nowUtc) {
  final riyadh = nowUtc.add(_riyadhOffset);
  final mm = riyadh.month.toString().padLeft(2, '0');
  final dd = riyadh.day.toString().padLeft(2, '0');
  return '${riyadh.year}-$mm-$dd';
}

/// Time from [nowUtc] until the next 00:00 Asia/Riyadh.
@visibleForTesting
Duration delayToNextRiyadhMidnightAt(DateTime nowUtc) {
  final riyadh = nowUtc.add(_riyadhOffset);
  final nextRiyadhMidnight =
      DateTime.utc(riyadh.year, riyadh.month, riyadh.day + 1);
  final nextResetUtc = nextRiyadhMidnight.subtract(_riyadhOffset);
  return nextResetUtc.difference(nowUtc);
}
