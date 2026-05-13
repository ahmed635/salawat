/// Single source of truth for Firestore document/collection paths.
/// Mirrors the schema documented in docs/FLUTTER-CONVERSION.md §5.
class FirestorePaths {
  FirestorePaths._();

  static const globalShards = 'globalShards';
  static String globalShard(int id) => 'globalShards/$id';

  /// Single-doc accumulator written only at UTC midnight by
  /// `resetGlobalCounter` (which rolls today's shard sum into it before
  /// zeroing the daily shards). Reading it + current `globalShards`
  /// gives the live all-time community total.
  static const lifetimeBankTotal = 'lifetimeBank/total';

  static const users = 'users';
  static String user(String uid) => 'users/$uid';

  static const leaderboardLifetime = 'leaderboardLifetime';
  static String leaderboardLifetimeUser(String uid) =>
      'leaderboardLifetime/$uid';

  static String leaderboardDailyUsers(String day) =>
      'leaderboardDaily/$day/users';
  static String leaderboardDailyUser(String day, String uid) =>
      'leaderboardDaily/$day/users/$uid';

  static String idempotency(String reqId) => 'idempotency/$reqId';
}
