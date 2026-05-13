/// Display-only disambiguator appended after a user's chosen name on
/// leaderboards. Two users who pick the same display name still render
/// distinctly because the tag is derived from their Firebase Auth uid,
/// which is stable across sessions.
///
/// Cosmetic only — collisions in the 4-digit space (1 in 10,000) just mean
/// two visually identical rows somewhere on the leaderboard, never any
/// data confusion (everything is uid-keyed under the hood).
library;

const _arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// Returns a 4-character Arabic-Indic-digit tag for the given uid, e.g. "٠١٢٣".
String userTag(String uid) {
  // FNV-1a 32-bit. Cheap, deterministic, no crypto dep — adequate for a
  // purely cosmetic discriminator.
  var hash = 0x811c9dc5;
  for (var i = 0; i < uid.length; i++) {
    hash ^= uid.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final n = hash % 10000;
  final buf = StringBuffer();
  buf.write(_arabicIndic[(n ~/ 1000) % 10]);
  buf.write(_arabicIndic[(n ~/ 100) % 10]);
  buf.write(_arabicIndic[(n ~/ 10) % 10]);
  buf.write(_arabicIndic[n % 10]);
  return buf.toString();
}
