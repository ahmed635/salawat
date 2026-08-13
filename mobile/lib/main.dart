import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
  // App Check must activate *before* any Cloud Functions or Firestore
  // call that hits an enforced endpoint, otherwise the first request
  // will be rejected with "App attestation failed". Release builds use
  // Play Integrity; debug builds use the debug provider (debug tokens
  // are registered in the Firebase Console → App Check → Debug tokens).
  //
  // Bounded + swallowed: activate() only registers the provider (the token
  // exchange itself is lazy), but it must never be what keeps the app on
  // the splash screen. A failure here degrades Cloud Function calls, not
  // startup.
  await FirebaseAppCheck.instance
      .activate(
        androidProvider:
            kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      )
      .timeout(const Duration(seconds: 3))
      .catchError((Object e) => debugPrint('[appcheck] activate failed: $e'));

  final prefs = await Prefs.load();

  // Pre-load audio assets so the very first tap doesn't pay the cost of
  // decoding the WAV (~10ms perceived latency saved).
  Audio.instance.init();

  runApp(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const SalawatApp(),
    ),
  );

  // Deliberately NOT awaited, and started only after runApp.
  //
  // init() subscribes to FCM topics, which is a network round-trip that the
  // SDK retries internally with no timeout — offline it simply never
  // returns. Awaiting it before runApp() meant a device with no connection
  // sat on the native splash forever, because runApp() was never reached.
  // Nothing in the first frame depends on notifications, so it runs in the
  // background and settles whenever the network allows.
  unawaited(NotificationService.instance.init());
}
