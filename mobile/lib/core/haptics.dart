import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Haptic feedback wrapper.
///
/// - [tap] uses the built-in [HapticFeedback] (no permission needed,
///   well-tuned by the OS for short interactions).
/// - [badgeUnlock] uses the `vibration` package for a custom pattern that
///   matches the React source's `navigator.vibrate([100, 50, 100])`.
class Haptics {
  Haptics._();

  static bool? _hasCustomVibrator;

  static Future<void> tap() => HapticFeedback.lightImpact();

  static Future<void> badgeUnlock() async {
    _hasCustomVibrator ??= await Vibration.hasVibrator();
    if (_hasCustomVibrator ?? false) {
      // Same pattern as the React app: buzz, pause, buzz.
      Vibration.vibrate(pattern: [0, 100, 50, 100]);
    } else {
      await HapticFeedback.heavyImpact();
    }
  }
}
