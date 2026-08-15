import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'counter_controller.dart';
import 'prefs.dart';

/// Bridge to the native quick-tap surfaces: the floating bubble and the
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
              // The day those taps were bucketed under, so the streak can be
              // credited to the day they were actually sent on.
              staleDay: isToday ? null : bufferedDay,
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
  ///
  /// The native side decides whether anything actually appears: it checks the
  /// user's preference, the overlay permission, and whether the bubble was
  /// dismissed since the app was last opened.
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

/// The permanent switch for the floating counter.
///
/// Distinct from dismissing the bubble, which is temporary and lives entirely
/// on the native side (`SalawatBuffer.dismissed`). This flag is only moved by
/// the first-run setup and the profile toggle; flicking the bubble onto the X
/// leaves it on, which is what lets the bubble come back by itself.
///
/// One flag covers the ongoing notification too, because that notification
/// isn't a surface the user chose — Android requires one to keep the overlay's
/// foreground service alive, so it lives and dies with the bubble.
class QuickTapController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.read(backgroundTapsProvider).isQuickTapEnabled();

  Future<void> setEnabled(bool value) async {
    state = AsyncData(value);
    await ref.read(backgroundTapsProvider).setQuickTapEnabled(value);
    // The permission gate below depends on the feature being on.
    ref.invalidate(overlayPermissionProvider);
  }

  /// Returns true if the caller should send the user to the overlay settings
  /// screen — without that permission there is nothing to show at all.
  Future<bool> toggle() async {
    final next = !(state.valueOrNull ?? false);
    await setEnabled(next);
    return next && !await ref.read(backgroundTapsProvider).canDrawOverlays();
  }

  /// Re-reads the native flag, in case something outside the app moved it.
  Future<void> refresh() async {
    state = AsyncData(await ref.read(backgroundTapsProvider).isQuickTapEnabled());
  }
}

final quickTapProvider =
    AsyncNotifierProvider<QuickTapController, bool>(QuickTapController.new);

/// Whether "display over other apps" is granted. Invalidated on resume, since
/// the only way to grant it is a trip to a system settings screen and back.
final overlayPermissionProvider = FutureProvider<bool>(
  (ref) => ref.read(backgroundTapsProvider).canDrawOverlays(),
);
