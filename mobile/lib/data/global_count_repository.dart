import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firestore_paths.dart';

/// Snapshot of the global community count plus a connectivity hint.
///
/// `isOffline` flips to true when the most recent attempt at a server-side
/// read failed (no network / Firestore unreachable / timed out). When that
/// happens we serve the most recent cached value so the UI keeps something
/// on screen — the home screen's ping dot turns red to signal staleness.
class GlobalCount {
  const GlobalCount({required this.count, required this.isOffline});

  final int count;
  final bool isOffline;
}

/// Reads the sharded global counters with a client-local 5-minute polling
/// cadence.
///
/// The previous design used a Firestore snapshot listener. At scale that
/// pattern was the dominant Firestore cost: every shard write fanned out
/// to one billed read on every device that had the home screen open. With
/// thousands of active users and ~35 shard writes/minute, that's tens of
/// millions of reads/day.
///
/// Polling locally on each device every 5 minutes drops the listener-side
/// cost to ~96 fetches/user/active-day per stream, which is several orders
/// of magnitude cheaper. Trade-off: the on-screen count only ticks every
/// 5 minutes, so users will see updates from other devices in stepwise
/// jumps rather than smoothly.
///
/// All-time community total is `lifetimeBank/total.count + sum(globalShards)`
/// — the bank doc is updated only once a day at UTC midnight (by
/// `resetGlobalCounter`); the live daily sum is added on each fetch.
class GlobalCountRepository {
  GlobalCountRepository(this._db);
  final FirebaseFirestore _db;

  // Tuned by the user: 5 minutes is a good balance between UI freshness
  // and Firestore cost. The fetch is local-clock driven (no server cron),
  // so each device's polling pace is independent.
  static const _refreshInterval = Duration(minutes: 5);

  // Cap a single fetch attempt so a hung network doesn't block the
  // periodic loop indefinitely. After timeout we fall back to cache.
  static const _fetchTimeout = Duration(seconds: 8);

  Stream<GlobalCount> watch() async* {
    yield await _fetchDaily();
    while (true) {
      await Future<void>.delayed(_refreshInterval);
      yield await _fetchDaily();
    }
  }

  Stream<int> watchLifetime() async* {
    yield await _fetchLifetime();
    while (true) {
      await Future<void>.delayed(_refreshInterval);
      yield await _fetchLifetime();
    }
  }

  Future<GlobalCount> _fetchDaily() async {
    final col = _db.collection(FirestorePaths.globalShards);
    try {
      final snap = await col
          .get(const GetOptions(source: Source.server))
          .timeout(_fetchTimeout);
      return GlobalCount(count: _sumCounts(snap), isOffline: false);
    } catch (_) {
      try {
        final cached = await col.get(const GetOptions(source: Source.cache));
        return GlobalCount(count: _sumCounts(cached), isOffline: true);
      } catch (_) {
        return const GlobalCount(count: 0, isOffline: true);
      }
    }
  }

  Future<int> _fetchLifetime() async {
    final bankRef = _db.doc(FirestorePaths.lifetimeBankTotal);
    final shardsCol = _db.collection(FirestorePaths.globalShards);
    try {
      final bankSnap = await bankRef
          .get(const GetOptions(source: Source.server))
          .timeout(_fetchTimeout);
      final shardSnap = await shardsCol
          .get(const GetOptions(source: Source.server))
          .timeout(_fetchTimeout);
      return _lifetimeOf(bankSnap, shardSnap);
    } catch (_) {
      try {
        final bankCached = await bankRef.get(const GetOptions(source: Source.cache));
        final shardCached =
            await shardsCol.get(const GetOptions(source: Source.cache));
        return _lifetimeOf(bankCached, shardCached);
      } catch (_) {
        return 0;
      }
    }
  }

  int _lifetimeOf(
    DocumentSnapshot<Map<String, dynamic>> bank,
    QuerySnapshot<Map<String, dynamic>> shards,
  ) {
    final banked = (bank.data()?['count'] as num?)?.toInt() ?? 0;
    return banked + _sumCounts(shards);
  }

  int _sumCounts(QuerySnapshot<Map<String, dynamic>> snap) {
    var total = 0;
    for (final doc in snap.docs) {
      total += (doc.data()['count'] as num?)?.toInt() ?? 0;
    }
    return total;
  }
}

final globalCountRepositoryProvider = Provider<GlobalCountRepository>((ref) {
  return GlobalCountRepository(FirebaseFirestore.instance);
});

final globalCountStreamProvider = StreamProvider<GlobalCount>((ref) {
  return ref.watch(globalCountRepositoryProvider).watch();
});

final globalLifetimeCountStreamProvider = StreamProvider<int>((ref) {
  return ref.watch(globalCountRepositoryProvider).watchLifetime();
});
