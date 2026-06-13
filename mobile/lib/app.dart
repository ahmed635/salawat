import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/daily_reset.dart';
import 'core/guide_controller.dart';
import 'core/theme_controller.dart';
import 'core/user_controller.dart';
import 'data/auth_repository.dart';
import 'data/counter_sync.dart';
import 'data/user_repository.dart';
import 'features/guide/guide_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/splash/splash_screen.dart';
import 'shared/nav_shell.dart';
import 'theme/app_theme.dart';
import 'theme/gold_mode.dart';

class SalawatApp extends ConsumerWidget {
  const SalawatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);
    final goldMode = ref.watch(goldModeProvider);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return MaterialApp(
      title: 'صلو عليه',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(goldMode: goldMode),
      darkTheme: AppTheme.dark(goldMode: goldMode),
      themeMode: themeMode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AuthGate(),
    );
  }
}

/// Waits for anonymous sign-in to complete, starts the counter sync, and
/// hands the user off to onboarding or the main shell. Also flushes the
/// pending counter delta when the app moves to the background.
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  bool _profileResynced = false;

  /// Minimum time the animated [SplashScreen] stays up, so its entrance
  /// animation always plays even when sign-in resolves instantly.
  static const _minSplash = Duration(milliseconds: 2500);
  bool _minSplashElapsed = false;
  Timer? _minSplashTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hand off from the native splash to our animated Flutter splash as soon
    // as the first frame is painted (that frame already shows SplashScreen),
    // so the user never sees a gap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
    _minSplashTimer = Timer(_minSplash, () {
      if (mounted) setState(() => _minSplashElapsed = true);
    });
  }

  @override
  void dispose() {
    _minSplashTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Best-effort flush before the user backgrounds / locks the device.
      ref.read(counterSyncProvider).flushNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(ensureSignedInProvider);

    // Keep the animated splash up until BOTH the minimum time has elapsed and
    // sign-in has resolved; only then route to the real screen.
    final Widget screen;
    if (!_minSplashElapsed) {
      screen = const SplashScreen(key: ValueKey('splash'));
    } else {
      screen = auth.when(
        loading: () => const SplashScreen(key: ValueKey('splash')),
        error: (e, _) => _AuthErrorScreen(key: const ValueKey('error'), error: e),
        data: (_) {
          // Now safe to start the periodic flush.
          ref.read(counterSyncProvider).start();
          // Reset the local "صلاة اليوم" at the user's local midnight.
          // The server resets the shared global counter at Asia/Riyadh
          // midnight on its own schedule.
          ref.read(dailyResetProvider).start();
          final userName = ref.watch(userNameControllerProvider);
          final guideSeen = ref.watch(guideControllerProvider);

          // One-shot resync for users whose displayName write was denied by
          // an earlier version of upsertProfile (it wrote disallowed fields).
          // Idempotent merge — no-op once users/{uid}.displayName matches.
          // Deferred off the build frame and error-swallowed: it's best-effort
          // and must never throw an unhandled async error or block the UI.
          if (!_profileResynced && userName != null && userName.isNotEmpty) {
            _profileResynced = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(userRepositoryProvider)
                  .upsertProfile(displayName: userName)
                  .catchError((Object e) =>
                      debugPrint('profile resync failed: $e'));
            });
          }

          // Flow: name onboarding → one-time how-to-use guide → main shell.
          if (userName == null) {
            return const OnboardingScreen(key: ValueKey('onboarding'));
          }
          if (!guideSeen) return const GuideScreen(key: ValueKey('guide'));
          return const NavShell(key: ValueKey('shell'));
        },
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: screen,
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({super.key, required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'تعذر الاتصال بالخادم.\n\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }
}
