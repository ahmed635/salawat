import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/audio.dart';
import 'core/notifications.dart';
import 'core/prefs.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
