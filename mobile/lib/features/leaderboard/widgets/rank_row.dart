import 'package:flutter/material.dart';

import '../../../core/arabic_numbers.dart';
import '../../../core/user_tag.dart';
import '../../../models/leaderboard_entry.dart';
import '../../../theme/colors.dart';

/// A single row in the leaderboard list. Mirrors the React source's design:
/// rank circle (special colors for top 3 + crown for #1), name, count.
class RankRow extends StatelessWidget {
  const RankRow({
    super.key,
    required this.entry,
    required this.position, // 1-based
    required this.isMe,
    this.isLast = false,
  });

  final LeaderboardEntry entry;
  final int position;
  final bool isMe;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isMe
            ? (isDark
                ? AppColors.emerald600.withValues(alpha: 0.2)
                : const Color(0xFFECFDF5))
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isLast
                ? Colors.transparent
                : (isDark
                    ? AppColors.slate700.withValues(alpha: 0.5)
                    : const Color(0xFFF1F5F9)),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _RankBadge(position: position, isDark: isDark),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: entry.name.isEmpty ? '—' : entry.name),
                    if (entry.name.isNotEmpty) ...[
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: userTag(entry.uid),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: (isMe
                                  ? (isDark
                                      ? const Color(0xFF34D399)
                                      : AppColors.emerald700)
                                  : (isDark
                                      ? AppColors.slate200
                                      : AppColors.slate800))
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: isMe
                      ? (isDark
                          ? const Color(0xFF34D399)
                          : AppColors.emerald700)
                      : (isDark ? AppColors.slate200 : AppColors.slate800),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              formatArabic(entry.count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: isDark
                    ? const Color(0xFF34D399)
                    : AppColors.emerald600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.position, required this.isDark});
  final int position;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final styling = _styleFor(position, isDark);
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: styling.bg,
        shape: BoxShape.circle,
      ),
      child: Text(
        position == 1 ? '👑' : '$position',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: styling.fg,
        ),
      ),
    );
  }

  static _RankStyle _styleFor(int position, bool isDark) {
    switch (position) {
      case 1:
        return _RankStyle(
          bg: isDark ? const Color(0x66713F12) : const Color(0xFFFEF3C7),
          fg: isDark ? AppColors.yellow400 : const Color(0xFFB45309),
        );
      case 2:
        return _RankStyle(
          bg: isDark ? AppColors.slate700 : AppColors.slate200,
          fg: isDark ? AppColors.slate100 : AppColors.slate700,
        );
      case 3:
        return _RankStyle(
          bg: isDark ? const Color(0x66713F12) : const Color(0xFFFDE68A),
          fg: isDark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
        );
      default:
        return _RankStyle(
          bg: isDark
              ? AppColors.slate800
              : const Color(0xFFF8FAFC),
          fg: isDark ? AppColors.slate400 : AppColors.slate500,
        );
    }
  }
}

class _RankStyle {
  const _RankStyle({required this.bg, required this.fg});
  final Color bg;
  final Color fg;
}
