import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Local notification orchestration. All channels are device-local — there
/// is no FCM token / push setup. Three kinds of notifications:
///
///  1. Daily reminders at 9 AM / 2 PM / 8 PM device-local — "لا تنسي الصلاة
///     على النبي". Repeating via [DateTimeComponents.time].
///  2. "New challenge" at 00:00 UTC — fired right around the server's
///     `resetGlobalCounter` daily reset. Body: "ها قد بدأ تحدي جديد".
///  3. "2M challenge" — fired imperatively from a Riverpod listener when the
///     live global count crosses the 1M daily goal. Gated to once per UTC
///     day via [Prefs.milestoneFiredOnUtcDay].
///
/// [Importance.high] + [Priority.high] so the OS delivers a heads-up banner.
/// [AndroidScheduleMode.inexactAllowWhileIdle] avoids the SCHEDULE_EXACT_ALARM
/// permission — daily reminders don't need second-level precision.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // 9 AM, 2 PM, 8 PM device-local. IDs 1..3.
  static const _reminderHours = [9, 14, 20];
  // Reserved IDs for the non-reminder notifications.
  static const _newChallengeId = 100;
  static const _milestoneId = 200;

  static const _channelId = 'salawat_reminders';
  static const _channelName = 'تذكير الصلاة على النبي';
  static const _channelDesc = 'تذكيرات يومية وتنبيهات التحديات';

  Future<void> init() async {
    if (_initialized) return;
    debugPrint('[notif] init: start');
    tzdata.initializeTimeZones();
    debugPrint('[notif] init: tzdata loaded');
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      debugPrint('[notif] init: device tz = $tzName');
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (e, st) {
      debugPrint('[notif] init: tz lookup failed ($e), falling back to UTC\n$st');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    final pluginReady = await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      // Fires when the user taps a notification while the app is alive
      // (foreground or backgrounded). Tapping a notification while the
      // app is terminated is handled by the Android intent re-launching
      // MainActivity — we then pick it up via getNotificationAppLaunchDetails
      // below so logs stay consistent.
      onDidReceiveNotificationResponse: _onTap,
    );
    debugPrint('[notif] init: plugin.initialize returned $pluginReady');
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    debugPrint('[notif] init: android impl resolved = ${androidImpl != null}');
    final permGranted = await androidImpl?.requestNotificationsPermission();
    debugPrint('[notif] init: POST_NOTIFICATIONS granted = $permGranted');

    // Cold-start case: app was terminated and the user tapped a notification
    // which relaunched MainActivity. Surface that so the app start log is
    // distinguishable from a plain launcher-icon tap, and so downstream
    // code (if any) can react to a notification-driven launch.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      final resp = launch?.notificationResponse;
      debugPrint(
        '[notif] launched from terminated tap: id=${resp?.id} payload=${resp?.payload}',
      );
    }

    _initialized = true;
    debugPrint('[notif] init: done');
  }

  /// Tap handler for notifications received while the app is running.
  /// MainActivity is already foregrounded by the time this fires (the
  /// underlying Android intent does that for us) — this hook is purely so
  /// we can log the tap, react to its payload, or navigate.
  void _onTap(NotificationResponse response) {
    debugPrint(
      '[notif] tap: id=${response.id} action=${response.actionId} payload=${response.payload}',
    );
  }

  /// Cancels and re-schedules the 3 daily reminders + the daily "new
  /// challenge" UTC-midnight notification. Idempotent — safe to call on
  /// every app start.
  Future<void> scheduleRecurring() async {
    debugPrint('[notif] scheduleRecurring: enter');
    try {
      if (!_initialized) await init();

      for (var i = 0; i < _reminderHours.length; i++) {
        await _plugin.cancel(i + 1);
      }
      await _plugin.cancel(_newChallengeId);
      debugPrint('[notif] scheduleRecurring: cancelled old slots');

      for (var i = 0; i < _reminderHours.length; i++) {
        final hour = _reminderHours[i];
        final now = tz.TZDateTime.now(tz.local);
        var firstFire =
            tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
        if (!firstFire.isAfter(now)) {
          firstFire = firstFire.add(const Duration(days: 1));
        }
        debugPrint('[notif] schedule reminder ${i + 1} at $firstFire');
        await _plugin.zonedSchedule(
          i + 1,
          'صلوا عليه',
          'لا تنسي الصلاة على النبي ﷺ',
          firstFire,
          _details(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }

      final utcNow = tz.TZDateTime.now(tz.UTC);
      var utcMidnight =
          tz.TZDateTime.utc(utcNow.year, utcNow.month, utcNow.day);
      if (!utcMidnight.isAfter(utcNow)) {
        utcMidnight = utcMidnight.add(const Duration(days: 1));
      }
      debugPrint('[notif] schedule new-challenge at $utcMidnight (UTC)');
      await _plugin.zonedSchedule(
        _newChallengeId,
        'صلوا عليه',
        'ها قد بدأ تحدي جديد',
        utcMidnight,
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );

      // Smoke test: fire one notification right now to confirm channel +
      // permissions + display all wire up correctly. Will disappear after
      // the user clears it; remove this block once the diagnostic is done.
      debugPrint('[notif] firing smoke-test notification');
      await _plugin.show(
        9999,
        'صلوا عليه',
        'تم تفعيل التذكيرات اليومية',
        _details(),
      );
      debugPrint('[notif] scheduleRecurring: done');
    } catch (e, st) {
      debugPrint('[notif] scheduleRecurring FAILED: $e\n$st');
    }
  }

  /// One-off celebration when the daily community goal is exceeded.
  Future<void> showMilestoneCrossed() async {
    if (!_initialized) await init();
    await _plugin.show(
      _milestoneId,
      'صلوا عليه',
      'بدأ تحدي ال 2 مليون',
      _details(),
    );
  }

  // Built lazily — AndroidNotificationDetails has no const constructor.
  //
  // `icon` is the small status-bar icon. Android always tints it to white,
  // so it must be a transparent-bg silhouette — we use the swirl-and-tap
  // glyph extracted from the logo at drawable-nodpi/notification_icon.png.
  //
  // `largeIcon` is the big artwork shown in the expanded notification
  // card; uses the full-colour circular logo at drawable-nodpi/app_logo.png.
  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'notification_icon',
        largeIcon: DrawableResourceAndroidBitmap('app_logo'),
      ),
    );
  }
}
