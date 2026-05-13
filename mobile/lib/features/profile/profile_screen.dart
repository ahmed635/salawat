// Hide Material's Badge widget so our model name resolves unambiguously.
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/committed_days_controller.dart';
import '../../core/lifetime_counter_controller.dart';
import '../../core/user_controller.dart';
import '../../core/user_tag.dart';
import '../../data/auth_repository.dart';
import '../../models/badge.dart';
import '../../theme/colors.dart';
import '../../theme/gold_mode.dart';
import 'widgets/badge_card.dart';
import 'widgets/profile_header.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Profile shows the lifetime count (since-install), not the daily one —
    // achievements need to persist across the midnight reset.
    final count = ref.watch(lifetimeCounterProvider);
    final userName = ref.watch(userNameControllerProvider) ?? '';
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    final tag = uid == null ? null : userTag(uid);
    final goldMode = ref.watch(goldModeProvider);
    final committedDays = ref.watch(committedDaysProvider);
    final unlockedCount = badges.where((b) => count >= b.requirement).length;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProfileHeader(
              userName: userName,
              count: count,
              tag: tag,
              goldMode: goldMode,
              committedDays: committedDays,
            ),
            const SizedBox(height: 24),
            _SectionTitle(
              isDark: isDark,
              unlocked: unlockedCount,
              total: badges.length,
            ),
            const SizedBox(height: 12),
            GridView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: badges.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.05,
              ),
              itemBuilder: (_, i) =>
                  BadgeCard(badge: badges[i], count: count),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.isDark,
    required this.unlocked,
    required this.total,
  });

  final bool isDark;
  final int unlocked;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.brightness_2,
                size: 20,
                color: AppColors.yellow500,
              ),
              const SizedBox(width: 8),
              Text(
                'سجل الأوسمة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : AppColors.slate800,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.slate800
                  : const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$unlocked / $total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? const Color(0xFF34D399)
                    : AppColors.emerald700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
