import 'package:flutter/material.dart';

import '../../../core/arabic_numbers.dart';
import '../../../models/badge.dart';
import '../../../theme/colors.dart';

class NextBadgeCard extends StatelessWidget {
  const NextBadgeCard({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final next = nextBadgeFor(count);
    final prev = previousBadgeRequirement(count);
    final span = next.requirement - prev;
    final progress = span <= 0
        ? 1.0
        : ((count - prev) / span).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.slate800.withValues(alpha: 0.5)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.slate700.withValues(alpha: 0.5)
              : AppColors.slate100,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: next.bg(brightness),
            ),
            child: Icon(next.icon, color: next.color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الهدف القادم: ${next.title}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.slate300 : AppColors.slate600,
                      ),
                    ),
                    Text(
                      formatArabic(next.requirement),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.slate400,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor:
                        isDark ? AppColors.slate700 : AppColors.slate100,
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
