import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/leaderboard_entry.dart';
import 'auth_repository.dart';
import 'firestore_paths.dart';
import 'today_riyadh.dart';

/// The visible leaderboard is the **daily** competition keyed by the
/// current Asia/Riyadh date. Resets every 00:00 Riyadh because:
///   - `incrementCount` writes into `leaderboardDaily/{todayRiyadh}/users/{uid}`
///   - `cleanupOldData` deletes yesterday's subcollection at midnight
///   - `todayRiyadhProvider` re-emits the new date, so the [StreamProvider]s
///     here automatically re-subscribe to the new empty subcollection.
class LeaderboardRepository {
  LeaderboardRepository(this._db);
  final FirebaseFirestore _db;

  /// Top [limit] users by today's salawat count, descending.
  Stream<List<LeaderboardEntry>> watchTop(String today, {int limit = 50}) {
    return _db
        .collection(FirestorePaths.leaderboardDailyUsers(today))
        .orderBy('count', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LeaderboardEntry.fromFirestore(d.id, d.data()))
            .toList(growable: false));
  }

  /// Live rank for [uid] within today's competition. Streams the user's
  /// own daily row, then on each change runs a `count()` aggregation
  /// for users above them in today's subcollection.
  ///
  /// Throttled the same way as before — at most one recompute every
  /// [_rankRecomputeWindow], plus a "count moved by >5" gate — so a
  /// burst of taps doesn't fan out into many aggregation queries.
  Stream<MyRank?> watchMyRank(String uid, String today) async* {
    final docStream = _db
        .doc(FirestorePaths.leaderboardDailyUser(today, uid))
        .snapshots();

    DateTime? lastFetched;
    int? lastFetchedRank;
    int? lastFetchedCount;

    await for (final snap in docStream) {
      if (!snap.exists) {
        yield null;
        continue;
      }
      final data = snap.data() ?? const <String, dynamic>{};
      final count = (data['count'] as num?)?.toInt() ?? 0;
      final name = (data['name'] as String?) ?? '';

      if (count == 0) {
        yield MyRank(uid: uid, rank: null, count: 0, name: name);
        continue;
      }

      final now = DateTime.now();
      final stale = lastFetched == null ||
          now.difference(lastFetched).compareTo(_rankRecomputeWindow) > 0;
      final countMovedSignificantly = lastFetchedCount == null ||
          (count - lastFetchedCount).abs() > 5;

      if (!stale && !countMovedSignificantly && lastFetchedRank != null) {
        yield MyRank(uid: uid, rank: lastFetchedRank, count: count, name: name);
        continue;
      }

      try {
        final agg = await _db
            .collection(FirestorePaths.leaderboardDailyUsers(today))
            .where('count', isGreaterThan: count)
            .count()
            .get();
        final usersAbove = agg.count ?? 0;
        final rank = usersAbove + 1;
        lastFetched = now;
        lastFetchedRank = rank;
        lastFetchedCount = count;
        yield MyRank(uid: uid, rank: rank, count: count, name: name);
      } catch (_) {
        yield MyRank(
          uid: uid,
          rank: lastFetchedRank,
          count: count,
          name: name,
        );
      }
    }
  }

  // 30s window keeps rank fresh enough for the user without firing a
  // count() aggregation on every tap burst. The "count moved by >5" gate
  // below still triggers a recompute on meaningful jumps inside the
  // window, so the UX cost is small but the aggregation-read savings are
  // significant at scale (each aggregation = ~1 read per 1000 docs above).
  static const _rankRecomputeWindow = Duration(seconds: 30);
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(FirebaseFirestore.instance);
});

final leaderboardTopProvider =
    StreamProvider<List<LeaderboardEntry>>((ref) {
  // ref.watch on todayRiyadhProvider means this rebuilds at every
  // Riyadh midnight — the leaderboard refreshes the moment the new
  // challenge begins, no user action required.
  final today = ref.watch(todayRiyadhProvider).valueOrNull;
  if (today == null) return const Stream.empty();
  return ref
      .watch(leaderboardRepositoryProvider)
      .watchTop(today, limit: 50);
});

final myRankProvider = StreamProvider<MyRank?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  final today = ref.watch(todayRiyadhProvider).valueOrNull;
  if (today == null) return Stream.value(null);
  return ref
      .watch(leaderboardRepositoryProvider)
      .watchMyRank(user.uid, today);
});
