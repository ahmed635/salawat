// We define our own gamification Badge model — hide Material's widget so the
// type name resolves unambiguously.
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio.dart';
import '../../core/counter_controller.dart';
import '../../core/haptics.dart';
import '../../data/global_count_repository.dart';
import '../../models/badge.dart';
import '../../theme/colors.dart';
import 'widgets/global_goal_card.dart';
import 'widgets/next_badge_card.dart';
import 'widgets/tap_button.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _dailyGlobalGoal = 1000000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterControllerProvider);
    // Live community total (sum of 10 sharded docs). Shows 0 until Firestore
    // delivers its first snapshot. `isOffline` is true when the latest
    // snapshot was served from cache — i.e. we've lost the backend.
    final globalSnapshot = ref.watch(globalCountStreamProvider).valueOrNull;
    final globalCount = globalSnapshot?.count ?? 0;
    final isOffline = globalSnapshot?.isOffline ?? false;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          children: [
            GlobalGoalCard(
              current: globalCount,
              goal: _dailyGlobalGoal,
              isOffline: isOffline,
            ),
            const SizedBox(height: 24),
            TapButton(
              count: count,
              onTap: (_) => _onTap(context, ref),
            ),
            const SizedBox(height: 24),
            NextBadgeCard(count: count),
          ],
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    // Fire audio + haptic in parallel — both are best-effort; never block.
    Audio.instance.playTap();
    Haptics.tap();

    final unlocked = await ref.read(counterControllerProvider.notifier).tap();
    if (unlocked != null && context.mounted) {
      Audio.instance.playAchievement();
      Haptics.badgeUnlock();
      _showBadgeUnlocked(context, unlocked);
    }
  }

  void _showBadgeUnlocked(BuildContext context, Badge badge) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    // SnackBar's default text colour assumes a dark surface. We override
    // the background with the badge's pastel/tinted bg, so we have to set
    // a matching text colour or it disappears against the light variant.
    final textColor = isDark ? AppColors.slate100 : AppColors.slate800;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: badge.bg(brightness),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.yellow400, width: 2),
        ),
        duration: const Duration(seconds: 10),
        content: Row(
          children: [
            Icon(badge.icon, color: badge.color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'تهانينا! حصلت على وسام: ${badge.title}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
