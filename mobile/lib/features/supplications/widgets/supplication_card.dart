import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/arabic_numbers.dart';
import '../../../models/supplication.dart';
import '../../../theme/colors.dart';

/// One salah-form tile: a filled numbered index, a color-coded source badge,
/// the Arabic text, and copy/share actions. Mirrors the card in the Stitch
/// reference, restyled with the app's palette so it adapts to light/dark.
class SupplicationCard extends StatelessWidget {
  const SupplicationCard({
    super.key,
    required this.supplication,
    required this.number,
  });

  final Supplication supplication;

  /// 1-based position, rendered as an Arabic-Indic digit in the index circle.
  final int number;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.slate700 : AppColors.slate200,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IndexCircle(number: number, isDark: isDark),
              _SourceBadge(
                source: supplication.source,
                tone: supplication.tone,
                isDark: isDark,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            supplication.arabic,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 18,
              height: 2.2,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.slate100 : AppColors.slate700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionButton(
                icon: Icons.copy_outlined,
                label: 'نسخ',
                isDark: isDark,
                onTap: () => _copy(context),
              ),
              const SizedBox(width: 4),
              _ActionButton(
                icon: Icons.share_outlined,
                label: 'مشاركة',
                isDark: isDark,
                onTap: () => _share(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: supplication.shareText));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          duration: Duration(seconds: 2),
          content: Text('تم نسخ الصيغة'),
        ),
      );
  }

  Future<void> _share(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      supplication.shareText,
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }
}

class _IndexCircle extends StatelessWidget {
  const _IndexCircle({required this.number, required this.isDark});
  final int number;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Filled deep-emerald circle with white digit, like the reference's
        // bg-primary chip.
        color: isDark ? AppColors.emerald700 : AppColors.emerald900,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        arabizeDigits('$number'),
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({
    required this.source,
    required this.tone,
    required this.isDark,
  });

  final String source;
  final SourceTone tone;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _palette(tone, isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        source,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: fg,
        ),
      ),
    );
  }

  /// (background, foreground) per tone, with a dark-mode variant.
  static (Color, Color) _palette(SourceTone tone, bool isDark) {
    switch (tone) {
      case SourceTone.agreed:
        return isDark
            ? (AppColors.emerald900, AppColors.emerald400)
            : (const Color(0xFFD1FAE5), AppColors.emerald800);
      case SourceTone.sahih:
        return isDark
            ? (AppColors.amber900, AppColors.amber300)
            : (const Color(0xFFFEF3C7), AppColors.amber800);
      case SourceTone.sunan:
        return isDark
            ? (AppColors.slate700, AppColors.slate300)
            : (AppColors.slate100, AppColors.slate600);
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isDark ? AppColors.slate400 : AppColors.slate500;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
