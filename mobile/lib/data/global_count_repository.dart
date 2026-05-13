import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firestore_paths.dart';

/// Snapshot of the global community count plus a connectivity hint.
///
/// `isOffline` is derived from Firestore's snapshot metadata — when the SDK
/// has lost contact with the backend it serves data from its local cache and
/// flips `isFromCache` to true. The home screen uses this to recolor the
/// "live" ping dot so the user knows their count is stale.
class GlobalCount {
  const GlobalCount({required this.count, required this.isOffline});

  final int count;
  final bool isOffline;
}

/// Streams the global community count by summing the 10 sharded counter docs.
/// Sharding sidesteps Firestore's ~1 write/sec/document throttle on the hot path.
class GlobalCountRepository {
  GlobalCountRepository(this._db);
  final FirebaseFirestore _db;

  Stream<GlobalCount> watch() {
    // includeMetadataChanges: true is required so we get a fresh emission
    // when only `isFromCache` flips (no data change). Without it the offline
    // dot would lag until the next shard write.
    return _db
        .collection(FirestorePaths.globalShards)
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      var total = 0;
      for (final doc in snap.docs) {
        total += (doc.data()['count'] as num?)?.toInt() ?? 0;
      }
      return GlobalCount(count: total, isOffline: snap.metadata.isFromCache);
    });
  }
}

final globalCountRepositoryProvider = Provider<GlobalCountRepository>((ref) {
  return GlobalCountRepository(FirebaseFirestore.instance);
});

final globalCountStreamProvider = StreamProvider<GlobalCount>((ref) {
  return ref.watch(globalCountRepositoryProvider).watch();
});
