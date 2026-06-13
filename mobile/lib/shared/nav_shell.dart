import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/arabic_numbers.dart';
import '../core/lifetime_counter_controller.dart';
import '../core/theme_controller.dart';
import '../core/user_controller.dart';
import '../features/home/home_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/supplications/supplications_screen.dart';
import '../theme/app_theme.dart';
import '../theme/gold_mode.dart';

class NavShell extends ConsumerStatefulWidget {
  const NavShell({super.key});

  @override
  ConsumerState<NavShell> createState() => _NavShellState();
}

class _NavShellState extends ConsumerState<NavShell> {
  int _index = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    SupplicationsScreen(),
    LeaderboardScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          _Header(isDark: isDark, brightness: brightness),
          Expanded(
            // IndexedStack keeps every tab alive (preserved scroll/state), but
            // Offstage does NOT pause tickers — so without this each hidden
            // screen's animations (rotating rings, ping dot, countdown) would
            // keep burning frames. TickerMode mutes the non-selected subtrees.
            child: IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < _screens.length; i++)
                  TickerMode(enabled: _index == i, child: _screens[i]),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'صيغ الصلاة',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'لوحة الشرف',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'إنجازاتي',
          ),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.isDark, required this.brightness});

  final bool isDark;
  final Brightness brightness;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaQuery = MediaQuery.of(context);
    final userName = ref.watch(userNameControllerProvider) ?? '';
    final goldMode = ref.watch(goldModeProvider);

    return Container(
      padding: EdgeInsets.fromLTRB(16, mediaQuery.padding.top + 12, 16, 20),
      decoration: BoxDecoration(
        gradient: AppTheme.headerGradient(brightness, goldMode: goldMode),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: const [
          BoxShadow(blurRadius: 12, color: Color(0x14000000), offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: Image.asset(
                        'assets/icon/app_icon_circle.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'صلوا عليه',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  userName.isEmpty ? 'مرحبا بك' : userName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    isDark ? Icons.light_mode : Icons.dark_mode,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () =>
                      ref.read(themeControllerProvider.notifier).toggle(),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.share, color: Colors.white, size: 20),
                  onPressed: () => _share(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final count = ref.watch(lifetimeCounterProvider);
    final text =
        'أنا وصلت لـ ${formatArabic(count)} صلاة على النبي ﷺ! '
        'شاركني الأجر وتحداني في لوحة الشرف 🌟';
    final box = context.findRenderObject() as RenderBox?;
    await Share.share(
      text,
      sharePositionOrigin:
          box != null ? box.localToGlobal(Offset.zero) & box.size : null,
    );
  }
}
