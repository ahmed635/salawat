import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'counter_controller.dart';
import 'prefs.dart';

/// Bridge to the native quick-tap surfaces: the ongoing notification and the
/// home-screen widget.
///
/// The counter itself never lives on the native side. Those surfaces only
/// *append* to a synchronized native buffer (`SalawatBuffer.kt`), and this
/// class drains that buffer into [CounterController] whenever Flutter is
/// running. That split is deliberate — see the doc comment in
/// `SalawatBuffer.kt` for why a second writer to the real counter would
/// corrupt `CounterSync`'s idempotency state.
///
/// Android-only. iOS has no equivalent surface and every call no-ops there.
class BackgroundTaps {
  BackgroundTaps(this._ref);

  static const _channel = MethodChannel('com.salawat.app/background_taps');

  final Ref _ref;

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Pulls buffered taps into the app's counters and pushes the resulting
  /// total back down so both surfaces render the real number.
  ///
  /// Safe to call repeatedly — the native drain is atomic, so a second call
  /// finds an empty buffer. Errors are swallowed: a failed reconcile must
  /// never keep the user out of the app, and the taps stay buffered for the
  /// next attempt.
  Future<void> reconcile() async {
    if (!_supported) return;
    try {
      final drained = await _channel.invokeMapMethod<String, dynamic>('drain');
      final today = (drained?['today'] as int?) ?? 0;
      final stale = (drained?['stale'] as int?) ?? 0;
      final bufferedDay = drained?['day'] as String?;

      if (today > 0 || stale > 0) {
        // The buffer bucketed these under `bufferedDay`. If the app is only
        // resuming now, on a later day, they are no longer "today" — demote
        // them so they land in the lifetime total instead of inflating the
        // current day's counter.
        final isToday = bufferedDay == null || bufferedDay == _todayLocal();
        await _ref.read(counterControllerProvider.notifier).addBackgroundTaps(
              today: isToday ? today : 0,
              stale: isToday ? stale : stale + today,
            );
      }

      await pushDisplay();
    } catch (e) {
      debugPrint('[bgtaps] reconcile failed: $e');
    }
  }

  /// Mirrors the current daily count down to the native surfaces.
  Future<void> pushDisplay() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('setDisplay', {
        'value': _ref.read(prefsProvider).localCount,
      });
    } catch (e) {
      debugPrint('[bgtaps] pushDisplay failed: $e');
    }
  }

  // --- Floating bubble ---

  Future<bool> canDrawOverlays() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sends the user to the system "Display over other apps" screen. There is
  /// no runtime-dialog path for this permission, so the caller has to re-check
  /// [canDrawOverlays] once the app resumes.
  Future<void> requestOverlayPermission() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('requestOverlayPermission');
    } catch (e) {
      debugPrint('[bgtaps] requestOverlayPermission failed: $e');
    }
  }

  Future<bool> isQuickTapEnabled() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('isQuickTapEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setQuickTapEnabled(bool enabled) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('setQuickTapEnabled', {'enabled': enabled});
      if (enabled) await pushDisplay();
    } catch (e) {
      debugPrint('[bgtaps] setQuickTapEnabled failed: $e');
    }
  }

  /// Shown on the way out of the app, hidden on the way back in — the bubble
  /// would only cover the real counter while the user is looking at it.
  Future<void> showOverlay() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('showOverlay');
    } catch (e) {
      debugPrint('[bgtaps] showOverlay failed: $e');
    }
  }

  Future<void> hideOverlay() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('hideOverlay');
    } catch (e) {
      debugPrint('[bgtaps] hideOverlay failed: $e');
    }
  }

  static String _todayLocal() {
    final d = DateTime.now();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

final backgroundTapsProvider = Provider<BackgroundTaps>(BackgroundTaps.new);

/// The single switch for background tapping.
///
/// One flag, one toggle. The bubble and the notification are two faces of the
/// same feature — and the notification is mandatory whenever the bubble runs,
/// since Android requires one for the overlay's foreground service. Two
/// separate switches meant turning "it" off could leave the other surface
/// alive, which reads as the feature refusing to die.
class QuickTapController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.read(backgroundTapsProvider).isQuickTapEnabled();

  /// Returns true if the caller should offer the overlay permission — the
  /// feature is on either way, it just falls back to the notification alone
  /// until the permission is granted.
  Future<bool> toggle() async {
    final taps = ref.read(backgroundTapsProvider);
    final next = !(state.valueOrNull ?? false);
    state = AsyncData(next);
    await taps.setQuickTapEnabled(next);
    return next && !await taps.canDrawOverlays();
  }

  /// Re-reads the native flag. The feature can be switched off from outside
  /// the app — the notification's "إيقاف" button, swiping it away, or a
  /// long-press on the bubble — so the toggle must not keep claiming it's on.
  Future<void> refresh() async {
    state = AsyncData(await ref.read(backgroundTapsProvider).isQuickTapEnabled());
  }
}

final quickTapProvider =
    AsyncNotifierProvider<QuickTapController, bool>(QuickTapController.new);
