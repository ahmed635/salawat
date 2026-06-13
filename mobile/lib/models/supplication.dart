import 'package:flutter/foundation.dart';

/// Visual tone of a source badge, mirroring the three badge colors used in the
/// "Daily Supplications" Stitch reference:
/// - [agreed]  → متفق عليه (mint / emerald)
/// - [sahih]   → الصحيحان: البخاري / مسلم (gold / amber)
/// - [sunan]   → كتب السنن والمسانيد: النسائي / أحمد (neutral / slate)
enum SourceTone { agreed, sahih, sunan }

/// A single salah-upon-the-Prophet ﷺ form shown on the "صيغ الصلاة" screen.
/// Content is curated and shipped with the app (no backend) — the list lives in
/// [supplications] below and is numbered by position.
@immutable
class Supplication {
  const Supplication({
    required this.arabic,
    required this.source,
    required this.tone,
  });

  /// The full Arabic text the user reads/recites.
  final String arabic;

  /// Source attribution shown in the badge, e.g. "متفق عليه".
  final String source;

  /// Drives the badge color.
  final SourceTone tone;

  /// What the share/copy action puts on the clipboard / share sheet.
  String get shareText => '$arabic\n\n— $source';
}

/// The authentic forms of salah upon the Prophet ﷺ, ordered as in the design
/// reference. Edit this list to add/remove cards — the screen renders it as-is.
const List<Supplication> supplications = [
  Supplication(
    arabic:
        'اللهم صل على محمد، وعلى آل محمد، كما صليت على إبراهيم، وعلى آل إبراهيم، '
        'إنك حميد مجيد، اللهم بارك على محمد، وعلى آل محمد، كما باركت على إبراهيم، '
        'وعلى آل إبراهيم، إنك حميد مجيد',
    source: 'متفق عليه',
    tone: SourceTone.agreed,
  ),
  Supplication(
    arabic:
        'اللهم صل على محمد، وعلى أزواجه وذريته، كما صليت على آل إبراهيم، '
        'وبارك على محمد، وعلى أزواجه وذريته، كما باركت على آل إبراهيم، إنك حميد مجيد',
    source: 'متفق عليه',
    tone: SourceTone.agreed,
  ),
  Supplication(
    arabic:
        'اللهم صل على محمد عبدك ورسولك، كما صليت على آل إبراهيم، '
        'وبارك على محمد عبدك ورسولك، وعلى آل محمد، كما باركت على إبراهيم، وعلى آل إبراهيم',
    source: 'رواه البخاري',
    tone: SourceTone.sahih,
  ),
  Supplication(
    arabic:
        'اللهم صل على محمد وعلى آل محمد، كما صليت على آل إبراهيم، '
        'وبارك على محمد، وعلى آل محمد، كما باركت على آل إبراهيم، في العالمين، إنك حميد مجيد',
    source: 'رواه مسلم',
    tone: SourceTone.sahih,
  ),
  Supplication(
    arabic:
        'اللهم صل على محمد، وعلى آل محمد، وبارك على محمد، وعلى آل محمد، '
        'كما صليت وباركت على إبراهيم، وآل إبراهيم، إنك حميد مجيد',
    source: 'رواه النسائي',
    tone: SourceTone.sunan,
  ),
  Supplication(
    arabic:
        'اللهم صل على محمد، وعلى آل محمد، كما صليت على إبراهيم، وآل إبراهيم، '
        'إنك حميد مجيد، وبارك على محمد، وعلى آل محمد، كما باركت على إبراهيم، '
        'وآل إبراهيم، إنك حميد مجيد',
    source: 'رواه أحمد',
    tone: SourceTone.sunan,
  ),
  Supplication(
    arabic:
        'اللهم صل على محمد، وعلى أزواجه وذريته، كما صليت على آل إبراهيم، '
        'إنك حميد مجيد، وبارك على محمد، وعلى أزواجه وذريته، كما باركت على آل إبراهيم، '
        'إنك حميد مجيد',
    source: 'رواه أحمد',
    tone: SourceTone.sunan,
  ),
];
