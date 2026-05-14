import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'core/daily_reset.dart';
import 'core/notifications.dart';
import 'core/prefs.dart';
import 'core/theme_controller.dart';
import 'core/user_controller.dart';
import 'data/auth_repository.dart';
import 'data/counter_sync.dart';
import 'data/global_count_repository.dart';
import 'data/user_repository.dart';
import 'features/onboarding/onboarding_screen.dart';
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
  bool _splashRemoved = false;

  /// Drops the native splash exactly once, after the first frame is laid
  /// out. Called from both the data and error branches so a missing
  /// network can't strand the user on a permanent emerald screen.
  void _removeSplashOnce() {
    if (_splashRemoved) return;
    _splashRemoved = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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

    return auth.when(
      loading: () => const _SignInSplash(),
      error: (e, _) {
        _removeSplashOnce();
        return _AuthErrorScreen(error: e);
      },
      data: (_) {
        _removeSplashOnce();
        // Now safe to start the periodic flush.
        ref.read(counterSyncProvider).start();
        // Reset the local "today's count" at UTC midnight, matching the
        // server's scheduled reset of the global shards.
        ref.read(dailyResetProvider).start();
        // Fire-and-forget one-shot seeding of `globalLifetimeShards` from the
        // existing `leaderboardLifetime` sum. Server-side marker doc makes
        // this safe under concurrent calls from multiple devices.
        _tryBackfillLifetimeShards(ref);
        // (Re)schedule daily reminder notifications + the UTC-midnight
        // "new challenge" alert. Idempotent — cancels and re-creates each
        // launch so timezone changes (e.g. travel, DST) are picked up.
        NotificationService.instance.scheduleRecurring();

        // Fire the "2M challenge has begun" notification the moment the
        // live global count exceeds the daily goal. Gated to once per UTC
        // day so a single device only buzzes once per cycle.
        ref.listen<AsyncValue<GlobalCount>>(
          globalCountStreamProvider,
          (_, next) {
            final count = next.valueOrNull?.count ?? 0;
            if (count > goldModeThreshold) {
              _maybeFireMilestone(ref);
            }
          },
        );
        final userName = ref.watch(userNameControllerProvider);

        // One-shot resync for users whose displayName write was denied by
        // an earlier version of upsertProfile (it wrote disallowed fields).
        // Idempotent merge — no-op once users/{uid}.displayName matches.
        if (!_profileResynced && userName != null && userName.isNotEmpty) {
          _profileResynced = true;
          ref.read(userRepositoryProvider).upsertProfile(displayName: userName);
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: userName == null
              ? const OnboardingScreen(key: ValueKey('onboarding'))
              : const NavShell(key: ValueKey('shell')),
        );
      },
    );
  }
}

Future<void> _maybeFireMilestone(WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  final today = _todayLocalDate();
  if (prefs.milestoneFiredOnUtcDay == today) return;
  await prefs.setMilestoneFiredOnUtcDay(today);
  await NotificationService.instance.showMilestoneCrossed();
}

// Gate is keyed on the user's own clock so each device sees one
// celebration per local calendar day. (Pref key still says "Utc" for
// backward-compat with existing installs; only the value semantics
// changed.)
String _todayLocalDate() {
  final d = DateTime.now();
  final mm = d.month.toString().padLeft(2, '0');
  final dd = d.day.toString().padLeft(2, '0');
  return '${d.year}-$mm-$dd';
}

Future<void> _tryBackfillLifetimeShards(WidgetRef ref) async {
  final prefs = ref.read(prefsProvider);
  if (prefs.lifetimeBackfillTried) return;
  await prefs.setLifetimeBackfillTried(true);
  try {
    await FirebaseFunctions.instance
        .httpsCallable('backfillLifetimeShards')
        .call();
  } catch (_) {
    // Best-effort. If it failed (no network, function not deployed yet, etc.)
    // the server-side marker doc keeps the next attempt safe — but we've
    // already set the local flag, so retries would only happen on reinstall.
    // That's fine: any other device will eventually run the seed.
  }
}

class _SignInSplash extends StatelessWidget {
  const _SignInSplash();
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.error});
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
