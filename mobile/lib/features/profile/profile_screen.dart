// Hide Material's Badge widget so our model name resolves unambiguously.
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_share.dart';
import '../../core/background_taps.dart';
import '../../core/committed_days_controller.dart';
import '../../core/lifetime_counter_controller.dart';
import '../../core/user_controller.dart';
import '../../core/user_tag.dart';
import '../../data/auth_repository.dart';
import '../../models/badge.dart';
import '../../theme/colors.dart';
import '../../theme/gold_mode.dart';
import '../guide/guide_screen.dart';
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
            const SizedBox(height: 20),
            _QuickTapToggle(isDark: isDark),
            const SizedBox(height: 12),
            _GuideButton(isDark: isDark),
            const SizedBox(height: 12),
            _ShareAppButton(isDark: isDark),
          ],
        ),
      ),
    );
  }
}

/// Reopens the one-time how-to-use guide in replay mode (it pops on finish,
/// and doesn't touch the first-launch flag).
class _GuideButton extends StatelessWidget {
  const _GuideButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return _ActionTile(
      isDark: isDark,
      icon: Icons.help_outline,
      label: 'كيف تستخدم التطبيق',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const GuideScreen(replay: true),
        ),
      ),
    );
  }
}

/// Opens the system share sheet with the store link. Unlike the header's
/// share button this one doesn't mention the user's count — it's an invite
/// to the app, not a brag about a score.
class _ShareAppButton extends StatelessWidget {
  const _ShareAppButton({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return _ActionTile(
      isDark: isDark,
      icon: Icons.share_outlined,
      label: 'شارك التطبيق',
      onTap: () => shareApp(context, appInviteText()),
    );
  }
}

/// The one switch for tapping without opening the app.
///
/// Turning it on offers the "Display over other apps" permission, which buys
/// the floating bubble. Declining isn't a dead end — the feature still works
/// from the notification, so the permission is an upgrade rather than a gate.
class _QuickTapToggle extends ConsumerWidget {
  const _QuickTapToggle({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    final on = ref.watch(quickTapProvider).valueOrNull ?? false;

    Future<void> handleToggle() async {
      final wantsOverlay = await ref.read(quickTapProvider.notifier).toggle();
      if (!wantsOverlay || !context.mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('العدّاد العائم'),
          content: const Text(
            'لعرض العدّاد كرقم عائم فوق التطبيقات الأخرى، يحتاج التطبيق إلى إذن '
            '"الظهور فوق التطبيقات الأخرى" من إعدادات النظام.\n\n'
            'بدون هذا الإذن سيعمل التسبيح السريع من الإشعار فقط.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('الإشعار يكفي'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      );
      if (go ?? false) {
        await ref.read(backgroundTapsProvider).requestOverlayPermission();
      }
    }

    return Material(
      color: isDark ? AppColors.slate800 : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: handleToggle,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.slate700 : AppColors.slate100,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bubble_chart_outlined,
                size: 22,
                color: isDark ? AppColors.emerald400 : AppColors.emerald600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'التسبيح السريع',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : AppColors.slate800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'عدّاد عائم للصلاة دون فتح التطبيق',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.slate400,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: on, onChanged: (_) => handleToggle()),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full-width row used by the actions under the badge grid.
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.isDark,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool isDark;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? AppColors.slate800 : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.slate700 : AppColors.slate100,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: isDark ? AppColors.emerald400 : AppColors.emerald600,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.slate800,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_left,
                size: 22,
                color: AppColors.slate400,
              ),
            ],
          ),
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
