import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio.dart';
import 'core/notifications.dart';
import 'core/prefs.dart';
import 'firebase_options.dart';

Future<void> main() async {
  // Hold the native splash on screen past Flutter's first frame. _AuthGate
  // is responsible for removing it once anonymous sign-in resolves (or
  // errors out), so the user never sees the bare auth-gate spinner.
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final prefs = await Prefs.load();

  // Pre-load audio assets so the very first tap doesn't pay the cost of
  // decoding the WAV (~10ms perceived latency saved).
  Audio.instance.init();

  // Initialize the local-notifications plugin + request POST_NOTIFICATIONS
  // on Android 13+. Scheduling itself happens later in _AuthGate once we
  // know the user is in the main shell.
  await NotificationService.instance.init();

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const SalawatApp(),
    ),
  );
}
