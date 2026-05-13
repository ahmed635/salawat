import 'package:flutter/material.dart';

import '../../../core/arabic_numbers.dart';
import '../../../theme/colors.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.userName,
    required this.count,
    this.tag,
    this.goldMode = false,
    this.committedDays,
  });

  final String userName;
  final int count;

  /// Optional 4-digit Arabic-Indic disambiguator shown after the name so
  /// the user knows what others see them as on the leaderboard.
  final String? tag;

  /// When true, the header swaps the emerald/teal gradient for an amber
  /// "gold" one to match the rest of the celebration state.
  final bool goldMode;

  /// Number of distinct UTC days the user has been active. When null the
  /// stat pill is hidden (keeps the widget usable from tests/screens that
  /// don't have a provider scope).
  final int? committedDays;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: isDark
              ? const [AppColors.slate800, AppColors.slate900]
              : (goldMode
                  ? const [AppColors.amber400, AppColors.amber700]
                  : const [AppColors.teal500, AppColors.emerald700]),
        ),
        borderRadius: BorderRadius.circular(40),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          PositionedDirectional(
            end: -40,
            top: -40,
            child: Opacity(
              opacity: 0.1,
              child: Icon(
                Icons.emoji_events,
                size: 160,
                color: Colors.white,
              ),
            ),
          ),
          Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.gps_fixed,
                  size: 40,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: userName),
                    if (tag != null && tag!.isNotEmpty && userName.isNotEmpty) ...[
                      const TextSpan(text: ' '),
                      TextSpan(
                        text: tag,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              _StatPill(label: 'حصيلتك:', value: count),
              if (committedDays != null) ...[
                const SizedBox(height: 8),
                _StatPill(
                  label: 'أيام الالتزام:',
                  value: committedDays!,
                  icon: Icons.event_available,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final int value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatArabic(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
