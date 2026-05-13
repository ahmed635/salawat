import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme_controller.dart';
import 'core/user_controller.dart';
import 'data/auth_repository.dart';
import 'data/counter_sync.dart';
import 'data/user_repository.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'shared/nav_shell.dart';
import 'theme/app_theme.dart';

class SalawatApp extends ConsumerWidget {
  const SalawatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return MaterialApp(
      title: 'صلوا عليه',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
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
      error: (e, _) => _AuthErrorScreen(error: e),
      data: (_) {
        // Now safe to start the periodic flush.
        ref.read(counterSyncProvider).start();
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
