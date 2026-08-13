import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/background_taps.dart';
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
import 'theme/colors.dart';
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
  bool _backgroundTapsReconciled = false;

  /// Minimum time the animated [SplashScreen] stays up, so its entrance
  /// animation always plays even when sign-in resolves instantly.
  ///
  /// Sized to the splash's 900ms entrance plus a beat to read the logo. The
  /// other two controllers there are `repeat()` loops with no end to wait
  /// for, so holding for their duration was pure dead time on every launch.
  static const _minSplash = Duration(milliseconds: 1100);
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
      // Hand the current total to the notification/widget on the way out.
      // Pushing per-tap instead would mean a platform-channel round trip on
      // every tap during rapid tapping, to update surfaces the user can't
      // see while they're looking at the app.
      ref.read(backgroundTapsProvider).pushDisplay();
      // Float the bubble only once we're actually out of the way — on top of
      // our own UI it would just cover the real counter.
      ref.read(backgroundTapsProvider).showOverlay();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(backgroundTapsProvider).hideOverlay();
      // Fold in anything tapped from the bubble, notification or widget while
      // we were away.
      ref.read(backgroundTapsProvider).reconcile();
      // Both surfaces can be switched off from outside the app — the
      // notification's "إيقاف" button, swiping it away, or long-pressing the
      // bubble. Re-read the native flags so the profile toggles don't sit
      // there claiming something is on after the user turned it off.
      ref.read(quickTapProvider.notifier).refresh();
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
        error: (e, _) => _AuthErrorScreen(
          key: const ValueKey('error'),
          error: e,
          onRetry: () => ref.invalidate(ensureSignedInProvider),
        ),
        data: (_) {
          // Now safe to start the periodic flush.
          ref.read(counterSyncProvider).start();
          // Reset the local "صلاة اليوم" at the user's local midnight.
          // The server resets the shared global counter at Asia/Riyadh
          // midnight on its own schedule.
          ref.read(dailyResetProvider).start();

          // Cold start doesn't emit a `resumed` lifecycle event, so the
          // buffered quick-taps need draining here too. Ordered after the
          // daily reset above so a day-rollover zeroes the counter *before*
          // buffered taps fold in, rather than being wiped by it.
          if (!_backgroundTapsReconciled) {
            _backgroundTapsReconciled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(backgroundTapsProvider).reconcile();
            });
          }
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

/// Shown when the very first anonymous sign-in fails — in practice, a fresh
/// install with no connection, since a returning user is served from the
/// persisted session. Retries by itself the moment the network comes back,
/// so regaining signal doesn't require a tap (let alone a force-quit).
class _AuthErrorScreen extends StatefulWidget {
  const _AuthErrorScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  State<_AuthErrorScreen> createState() => _AuthErrorScreenState();
}

class _AuthErrorScreenState extends State<_AuthErrorScreen> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounce;
  bool _retrying = false;

  /// The radio reports a usable link before it can actually carry a request
  /// (same lag `GlobalCountRepository` backs off around), and the interfaces
  /// settling can emit several events in a row. Debouncing by this much
  /// collapses the burst and spends the retry on a link that's ready.
  static const _settleDelay = Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    // Only transitions matter. A retry is not scheduled for whatever state
    // the device is already in, so a connection that's up but not working
    // (captive portal, no data balance) can't spin us in a retry loop — the
    // button is the way out of that one.
    _sub = Connectivity().onConnectivityChanged.listen(_onConnectivityChanged);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final none = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    if (none || _retrying) return;
    _debounce?.cancel();
    _debounce = Timer(_settleDelay, () {
      if (!mounted) return;
      setState(() => _retrying = true);
      widget.onRetry();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _retryNow() {
    _debounce?.cancel();
    setState(() => _retrying = true);
    widget.onRetry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off,
                size: 44,
                color: AppColors.slate400,
              ),
              const SizedBox(height: 16),
              const Text(
                'تعذر الاتصال بالخادم',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'تحقق من اتصالك بالإنترنت ثم أعد المحاولة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.slate400),
              ),
              const SizedBox(height: 20),
              if (_retrying)
                const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                FilledButton(
                  onPressed: _retryNow,
                  child: const Text('إعادة المحاولة'),
                ),
              const SizedBox(height: 24),
              // Kept for field diagnostics, de-emphasised so it doesn't read
              // as the main message.
              Text(
                '${widget.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.slate400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
