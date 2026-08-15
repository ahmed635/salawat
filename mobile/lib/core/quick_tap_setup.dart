import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/colors.dart';
import 'background_taps.dart';
import 'prefs.dart';

/// The one and only time the app asks for the floating counter.
///
/// Runs once the user reaches the main shell for the first time — after name
/// onboarding and the how-to guide, so it lands on someone who already knows
/// what the app is for rather than on a stranger at a permission wall.
///
/// "Once" is enforced by [Prefs.quickTapSetupDone], which is written the
/// moment the sheet is *shown*. Declining closes the question permanently:
/// "display over other apps" has no runtime dialog, only a trip to a system
/// settings screen, and re-offering that on later launches is exactly the
/// nagging this flow exists to avoid. The profile toggle stays as the way back
/// in for anyone who changes their mind.
///
/// Note that dismissing the bubble later never reopens this — see
/// `SalawatBuffer.dismissed` on the native side. The permission was granted
/// once and is never handed back, so there is nothing left to ask for.
class QuickTapSetup {
  const QuickTapSetup._();

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> runIfNeeded(BuildContext context, WidgetRef ref) async {
    if (!_supported) return;
    final prefs = ref.read(prefsProvider);
    if (prefs.quickTapSetupDone) return;

    // Claim the one-shot before anything can interrupt: the accept path sends
    // the user to a settings screen, and an app killed there must not come
    // back asking again.
    await prefs.setQuickTapSetupDone(true);

    final taps = ref.read(backgroundTapsProvider);

    // Already granted — a reinstall, or a user who found the settings screen
    // on their own. Nothing to ask, just switch it on.
    if (await taps.canDrawOverlays()) {
      await ref.read(quickTapProvider.notifier).setEnabled(true);
      return;
    }

    if (!context.mounted) return;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickTapSheet(),
    );
    if (accepted != true) return;

    await ref.read(quickTapProvider.notifier).setEnabled(true);
    await taps.requestOverlayPermission();
  }
}

class _QuickTapSheet extends StatelessWidget {
  const _QuickTapSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.slate700 : AppColors.slate200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            // The bubble itself, at the size it will actually appear — the
            // fastest way to explain "a floating circle over your screen".
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.teal600, AppColors.emerald900],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.emerald900.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text(
                '٣٣',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'العدّاد العائم',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.slate800,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'زر صغير يطفو فوق التطبيقات الأخرى، تصلّي منه على النبي ﷺ '
              'دون فتح التطبيق. اسحبه إلى علامة ✕ لإخفائه، ويعود وحده في '
              'المرة القادمة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: AppColors.slate400,
              ),
            ),
            const SizedBox(height: 18),
            // Said plainly and up front. Both of these are visible consequences
            // the user will meet within seconds of accepting, and discovering
            // them afterwards is what makes a permission feel like a trick.
            _Note(
              isDark: isDark,
              icon: Icons.open_in_new,
              text: 'سيفتح إعداد النظام «العرض فوق التطبيقات الأخرى» لتفعيله.',
            ),
            const SizedBox(height: 10),
            _Note(
              isDark: isDark,
              icon: Icons.notifications_none,
              text: 'يرافقه إشعار صامت ثابت — يشترطه أندرويد لإبقاء الزر ظاهرًا.',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'تفعيل',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'ليس الآن',
                style: TextStyle(color: AppColors.slate400),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.isDark, required this.icon, required this.text});

  final bool isDark;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: isDark ? AppColors.emerald400 : AppColors.emerald600,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: isDark ? AppColors.slate300 : AppColors.slate500,
            ),
          ),
        ),
      ],
    );
  }
}
