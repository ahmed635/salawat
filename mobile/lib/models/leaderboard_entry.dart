/// One row in the leaderboard. Sourced from `leaderboardLifetime/{uid}`
/// (or `leaderboardDaily/{day}/users/{uid}` later for the daily view).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.name,
    required this.count,
  });

  final String uid;
  final String name;
  final int count;

  factory LeaderboardEntry.fromFirestore(String uid, Map<String, dynamic> data) {
    return LeaderboardEntry(
      uid: uid,
      name: (data['name'] as String?) ?? '',
      count: (data['count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The current user's place in the world. [rank] is null if the user has
/// never tapped (no leaderboard doc yet).
class MyRank {
  const MyRank({
    required this.uid,
    required this.rank,
    required this.count,
    required this.name,
  });

  final String uid;
  final int? rank;
  final int count;
  final String name;

  bool get isInTopList => rank != null && rank! <= 50;
}
