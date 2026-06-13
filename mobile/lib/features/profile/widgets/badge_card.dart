// Hide Material's Badge widget so our model name resolves unambiguously.
import 'package:flutter/material.dart' hide Badge;

import '../../../core/arabic_numbers.dart';
import '../../../models/badge.dart';
import '../../../theme/colors.dart';

class BadgeCard extends StatelessWidget {
  const BadgeCard({
    super.key,
    required this.badge,
    required this.count,
  });

  final Badge badge;
  final int count;

  bool get _unlocked => count >= badge.requirement;
  double get _progress => (count / badge.requirement).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final unlocked = _unlocked;

    return Semantics(
      label: '${badge.title}، ${unlocked ? 'وسام مفتوح' : 'مغلق'}، '
          'يفتح عند ${formatArabic(badge.requirement)} صلاة',
      excludeSemantics: true,
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unlocked
            ? badge.bg(brightness)
            : (isDark
                ? AppColors.slate800.withValues(alpha: 0.5)
                : Colors.white),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: unlocked
              ? Colors.transparent
              : (isDark
                  ? AppColors.slate700.withValues(alpha: 0.5)
                  : AppColors.slate100),
        ),
        boxShadow: unlocked
            ? const [
                BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 1)),
              ]
            : null,
      ),
      child: Column(
        children: [
          if (unlocked)
            // Soft white glow in the corner of unlocked tiles, mirroring the
            // React `bg-white/20 blur-xl` decorative element.
            ...const [
              SizedBox(height: 0),
            ],
          Icon(
            badge.icon,
            size: 32,
            color: unlocked
                ? badge.color
                : (isDark ? AppColors.slate600 : AppColors.slate300),
          ),
          const SizedBox(height: 8),
          Text(
            badge.title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: unlocked
                  ? (isDark ? AppColors.slate100 : AppColors.slate800)
                  : AppColors.slate400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatArabic(badge.requirement),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: unlocked
                  ? (isDark ? AppColors.slate300 : AppColors.slate600)
                  : AppColors.slate400,
            ),
          ),
          if (!unlocked) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 4,
                backgroundColor: isDark ? AppColors.slate700 : AppColors.slate100,
                valueColor: AlwaysStoppedAnimation(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }
}
