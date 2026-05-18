import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firestore_paths.dart';

/// Snapshot of the global community count plus a connectivity hint.
///
/// `isOffline` flips to true when the device drops its network (detected
/// instantly via [Connectivity]) or when a server-side read fails. While
/// offline we keep showing the last known count from cache so the home
/// screen never goes blank — the ping dot just turns red to signal
/// staleness.
class GlobalCount {
  const GlobalCount({required this.count, required this.isOffline});

  final int count;
  final bool isOffline;
}

/// Reads the sharded global counters with a client-local 1-minute polling
/// cadence, layered with immediate connectivity-change reactions.
///
/// Two triggers can cause a new value to flow out:
///   1. The periodic timer fires (every 1 min while a listener is alive).
///   2. The OS reports a network-state change. Going offline emits a
///      new [GlobalCount] with `isOffline: true` immediately (no waiting
///      for the next poll to fail). Coming back online triggers a fresh
///      fetch so the count refreshes instantly too.
///
/// All-time community total is `lifetimeBank/total.count + sum(globalShards)`
/// — the bank doc is updated only once a day at 00:00 Asia/Riyadh by
/// `resetGlobalCounter`; the live daily sum is added on each fetch.
class GlobalCountRepository {
  GlobalCountRepository(this._db);
  final FirebaseFirestore _db;

  // Tuned by the user: 1 minute is the freshness floor for "this is the
  // community total *right now*". Lower than 1 min and we start paying
  // serious Firestore-read bills for active users.
  static const _refreshInterval = Duration(minutes: 1);

  // Cap a single fetch attempt so a hung network doesn't block the
  // periodic loop indefinitely. After timeout we fall back to cache.
  static const _fetchTimeout = Duration(seconds: 8);

  Stream<GlobalCount> watch() => _streamFor(_fetchDaily);

  Stream<int> watchLifetime() {
    // Lifetime stream doesn't carry an isOffline flag in its public type,
    // so a simple polling loop is enough; no need for the connectivity
    // overlay. (Wraps so we still react to "online again" by triggering
    // a fresh fetch on the next poll naturally.)
    return _periodic(_fetchLifetime).map((c) => c.count);
  }

  /// Polling loop with a connectivity overlay. Yields [GlobalCount] on:
  /// (a) initial subscribe, (b) every [_refreshInterval], (c) every
  /// connectivity change. Going offline emits the last known count with
  /// `isOffline: true` without waiting for the next poll.
  Stream<GlobalCount> _streamFor(
    Future<GlobalCount> Function() fetch,
  ) {
    late StreamController<GlobalCount> controller;
    Timer? timer;
    StreamSubscription<List<ConnectivityResult>>? connSub;
    GlobalCount last = const GlobalCount(count: 0, isOffline: false);
    var disposed = false;

    Future<void> doFetch() async {
      final v = await fetch();
      if (disposed || controller.isClosed) return;
      last = v;
      controller.add(v);
    }

    void emitOffline() {
      if (disposed || controller.isClosed) return;
      if (last.isOffline) return; // already red
      last = GlobalCount(count: last.count, isOffline: true);
      controller.add(last);
    }

    controller = StreamController<GlobalCount>(
      onListen: () async {
        // Kick off with one fetch so the UI has something to show.
        await doFetch();
        timer = Timer.periodic(_refreshInterval, (_) => doFetch());
        connSub = Connectivity().onConnectivityChanged.listen((results) async {
          final none = results.isEmpty ||
              results.every((r) => r == ConnectivityResult.none);
          if (none) {
            emitOffline();
          } else {
            // Connectivity restored. The OS-level event fires the moment
            // the radio reports a link, but Firestore's internal channel
            // can linger in offline mode for a while after a blip — so a
            // Source.server read fired right now will just time out and
            // fall back to cache, leaving the dot stuck on red until the
            // next 1-minute poll (which may also be too early). Poke the
            // SDK back online and retry with a short backoff so we
            // recover within seconds instead of minutes.
            try {
              await _db.enableNetwork();
            } catch (_) {}
            for (final delay in const [0, 2, 6]) {
              if (disposed) return;
              if (delay > 0) {
                await Future<void>.delayed(Duration(seconds: delay));
                if (disposed) return;
              }
              await doFetch();
              if (!last.isOffline) break;
            }
          }
        });
      },
      onCancel: () async {
        disposed = true;
        timer?.cancel();
        await connSub?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<GlobalCount> _periodic(Future<GlobalCount> Function() fetch) async* {
    yield await fetch();
    while (true) {
      await Future<void>.delayed(_refreshInterval);
      yield await fetch();
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

  Future<GlobalCount> _fetchLifetime() async {
    final bankRef = _db.doc(FirestorePaths.lifetimeBankTotal);
    final shardsCol = _db.collection(FirestorePaths.globalShards);
    try {
      final bankSnap = await bankRef
          .get(const GetOptions(source: Source.server))
          .timeout(_fetchTimeout);
      final shardSnap = await shardsCol
          .get(const GetOptions(source: Source.server))
          .timeout(_fetchTimeout);
      return GlobalCount(
        count: _lifetimeOf(bankSnap, shardSnap),
        isOffline: false,
      );
    } catch (_) {
      try {
        final bankCached =
            await bankRef.get(const GetOptions(source: Source.cache));
        final shardCached =
            await shardsCol.get(const GetOptions(source: Source.cache));
        return GlobalCount(
          count: _lifetimeOf(bankCached, shardCached),
          isOffline: true,
        );
      } catch (_) {
        return const GlobalCount(count: 0, isOffline: true);
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
