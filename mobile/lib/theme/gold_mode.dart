import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/global_count_repository.dart';

/// True when the global community count has crossed the daily goal. The
/// whole app — header gradient, tap button, accents, Material primary
/// color — swaps to a gold palette as a celebration. Reverts when the
/// server's `resetGlobalCounter` scheduled function zeros the shards at
/// 00:00 Asia/Riyadh.
const goldModeThreshold = 1000000;

final goldModeProvider = Provider<bool>((ref) {
  // select() so dependents (whole-app theme, tap button, header) only rebuild
  // when the gold threshold is actually crossed — not on every count tick.
  return ref.watch(
    globalCountStreamProvider.select(
      (async) => (async.valueOrNull?.count ?? 0) > goldModeThreshold,
    ),
  );
});
