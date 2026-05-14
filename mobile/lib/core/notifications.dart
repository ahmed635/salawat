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
    tzdata.initializeTimeZones();
    try {
      final tzName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(tzName));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      // Fires when the user taps a notification while the app is alive
      // (foreground or backgrounded). Cold-start taps (process was dead)
      // relaunch MainActivity via the plugin's default content intent
      // — Android handles that part for us, so we only need this hook
      // here for in-process taps and future payload-based routing.
      onDidReceiveNotificationResponse: _onTap,
    );
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Android 13+ runtime permission. No-op on older versions.
    await androidImpl?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Tap handler for notifications received while the process is alive.
  /// MainActivity is already foregrounded by the time this fires — this
  /// hook is the seam for future payload-based routing (deep-link into
  /// a specific screen, etc.). Currently a no-op.
  void _onTap(NotificationResponse response) {}

  /// Cancels and re-schedules the 3 daily reminders + the daily "new
  /// challenge" UTC-midnight notification. Idempotent — safe to call on
  /// every app start.
  Future<void> scheduleRecurring() async {
    try {
      if (!_initialized) await init();

      for (var i = 0; i < _reminderHours.length; i++) {
        await _plugin.cancel(i + 1);
      }
      await _plugin.cancel(_newChallengeId);

      for (var i = 0; i < _reminderHours.length; i++) {
        final hour = _reminderHours[i];
        final now = tz.TZDateTime.now(tz.local);
        var firstFire =
            tz.TZDateTime(tz.local, now.year, now.month, now.day, hour);
        if (!firstFire.isAfter(now)) {
          firstFire = firstFire.add(const Duration(days: 1));
        }
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

      // New-challenge notification — tied to the global counter's reset,
      // which the server schedules at 00:00 Asia/Riyadh. Passing a Riyadh
      // TZDateTime + matchDateTimeComponents: time means the plugin
      // repeats at Riyadh midnight daily, which is the actual instant the
      // global counter zeros — even for users in other timezones.
      final riyadh = tz.getLocation('Asia/Riyadh');
      final riyadhNow = tz.TZDateTime.now(riyadh);
      var riyadhMidnight = tz.TZDateTime(
        riyadh,
        riyadhNow.year,
        riyadhNow.month,
        riyadhNow.day,
      );
      if (!riyadhMidnight.isAfter(riyadhNow)) {
        riyadhMidnight = riyadhMidnight.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        _newChallengeId,
        'صلوا عليه',
        'ها قد بدأ تحدي جديد',
        riyadhMidnight,
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e, st) {
      // Keep this one log — scheduling has died silently in the past and
      // it took a long debugging session to find out why. Without this
      // line a fresh regression would once again hide as "notifications
      // just don't work".
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
