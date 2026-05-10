import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firestore_paths.dart';

/// Streams the global community count by summing the 10 sharded counter docs.
/// Sharding sidesteps Firestore's ~1 write/sec/document throttle on the hot path.
class GlobalCountRepository {
  GlobalCountRepository(this._db);
  final FirebaseFirestore _db;

  Stream<int> watch() {
    return _db.collection(FirestorePaths.globalShards).snapshots().map((snap) {
      var total = 0;
      for (final doc in snap.docs) {
        total += (doc.data()['count'] as num?)?.toInt() ?? 0;
      }
      return total;
    });
  }
}

final globalCountRepositoryProvider = Provider<GlobalCountRepository>((ref) {
  return GlobalCountRepository(FirebaseFirestore.instance);
});

final globalCountStreamProvider = StreamProvider<int>((ref) {
  return ref.watch(globalCountRepositoryProvider).watch();
});
