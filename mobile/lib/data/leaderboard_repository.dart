import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/leaderboard_entry.dart';
import 'auth_repository.dart';
import 'firestore_paths.dart';

class LeaderboardRepository {
  LeaderboardRepository(this._db);
  final FirebaseFirestore _db;

  /// Top [limit] users by lifetime count, descending. Auto-refreshes via
  /// Firestore snapshots — no polling.
  Stream<List<LeaderboardEntry>> watchTop({int limit = 50}) {
    return _db
        .collection(FirestorePaths.leaderboardLifetime)
        .orderBy('count', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => LeaderboardEntry.fromFirestore(d.id, d.data()))
            .toList(growable: false));
  }

  /// Live rank for [uid]. Streams the user's own leaderboard doc, then on
  /// each change runs a `count()` aggregation for users above them. Throttled
  /// so a burst of taps doesn't fire many aggregation queries — at most one
  /// recompute per [_rankRecomputeWindow].
  ///
  /// At ~100K users this aggregation costs ~1 read per ~1000 docs above the
  /// user, billed once per recompute. At >500K users we'd want to switch to
  /// a tier display ("Top 1%") instead of exact rank.
  Stream<MyRank?> watchMyRank(String uid) async* {
    final docStream = _db
        .doc(FirestorePaths.leaderboardLifetimeUser(uid))
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

      // Use the previously-fetched rank if it's recent and the count change
      // is small — avoids a Firestore read on every tap.
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
            .collection(FirestorePaths.leaderboardLifetime)
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
        // If the aggregation fails (offline, permission, etc.) emit best-effort
        // with whatever we last knew.
        yield MyRank(
          uid: uid,
          rank: lastFetchedRank,
          count: count,
          name: name,
        );
      }
    }
  }

  static const _rankRecomputeWindow = Duration(seconds: 5);
}

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) {
  return LeaderboardRepository(FirebaseFirestore.instance);
});

final leaderboardTopProvider =
    StreamProvider<List<LeaderboardEntry>>((ref) {
  return ref.watch(leaderboardRepositoryProvider).watchTop(limit: 50);
});

final myRankProvider = StreamProvider<MyRank?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(leaderboardRepositoryProvider).watchMyRank(user.uid);
});
