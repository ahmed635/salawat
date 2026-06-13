import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/guide_controller.dart';
import '../../theme/colors.dart';
import 'widgets/guide_mockups.dart';

/// One-time how-to-use guide. A horizontal walkthrough of the app's screens,
/// each with a stylized mini-preview and an Arabic explanation.
///
/// Shown automatically by `_AuthGate` once after name onboarding (gated by
/// [guideControllerProvider]). Also reachable later from the profile screen via
/// [replay] = true, in which case finishing just pops instead of flipping the
/// one-time flag.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key, this.replay = false});

  /// True when opened manually from the profile screen (pushed as a route),
  /// false for the first-launch auto-show driven by the auth gate.
  final bool replay;

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = <_GuidePage>[
    _GuidePage(
      title: 'مرحبًا بك في مليون الصلاة على النبي ﷺ',
      body: 'هذا دليل سريع يعرّفك على شاشات التطبيق وطريقة استخدامه. '
          'تنقّل بين الصفحات لتبدأ رحلتك في الصلاة على النبي ﷺ.',
      visual: _LogoVisual(),
    ),
    _GuidePage(
      title: 'الرئيسية',
      body: 'اضغط الزر الكبير لتسجِّل صلاتك على النبي ﷺ. '
          'تابع عدد صلواتك اليوم، والهدف اليومي للمجتمع.',
      visual: PhoneFrame(child: HomeMock()),
    ),
    _GuidePage(
      title: 'صيغ الصلاة',
      body: 'اطّلع على صيغ الصلاة الثابتة على النبي ﷺ مع مصادرها، '
          'وانسخها أو شاركها بلمسة واحدة.',
      visual: PhoneFrame(child: SalawatMock()),
    ),
    _GuidePage(
      title: 'لوحة الشرف',
      body: 'نافِس الذاكرين حول العالم. تابع ترتيبك اليومي، '
          'وإجمالي صلوات المجتمع كاملًا.',
      visual: PhoneFrame(child: LeaderboardMock()),
    ),
    _GuidePage(
      title: 'إنجازاتي',
      body: 'اجمع الأوسمة كلما زادت صلواتك. '
          'أوسمتك تبقى لك مدى الحياة ولا تُمحى عند تجديد اليوم.',
      visual: PhoneFrame(child: ProfileMock()),
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish() async {
    if (widget.replay) {
      Navigator.of(context).pop();
    } else {
      // Flips the one-time flag; _AuthGate's AnimatedSwitcher then swaps in
      // the main shell.
      await ref.read(guideControllerProvider.notifier).markSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.slate900 : AppColors.slate50,
      body: SafeArea(
        child: Column(
          children: [
            // Skip — hidden on the last page where the primary button reads "ابدأ".
            SizedBox(
              height: 48,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedOpacity(
                  opacity: _isLast ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: TextButton(
                    onPressed: _isLast ? null : _finish,
                    child: Text(
                      'تخطّي',
                      style: TextStyle(
                        color: isDark ? AppColors.slate400 : AppColors.slate500,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _PageBody(page: _pages[i], isDark: isDark),
              ),
            ),
            _Dots(count: _pages.length, active: _page),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: _next,
                  child: Text(_isLast ? 'ابدأ الآن' : 'التالي'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page, required this.isDark});
  final _GuidePage page;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Expanded(child: Center(child: page.visual)),
          const SizedBox(height: 24),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : AppColors.slate800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.8,
              color: isDark ? AppColors.slate400 : AppColors.slate500,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.active});
  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == active ? AppColors.emerald600 : AppColors.slate300,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );
  }
}

class _GuidePage {
  const _GuidePage({
    required this.title,
    required this.body,
    required this.visual,
  });

  final String title;
  final String body;
  final Widget visual;
}

/// First page hero — the app logo inside the phone-frame's place.
class _LogoVisual extends StatelessWidget {
  const _LogoVisual();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.emerald600.withValues(alpha: 0.35),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset('assets/icon/app_icon_circle.png',
                fit: BoxFit.cover),
          ),
        ),
      ],
    );
  }
}
