import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notification orchestration backed by FCM topics.
///
/// All five notification kinds — three daily reminders, the new-challenge
/// alert at Riyadh midnight, and the 2M milestone — are now delivered by
/// the server via Firebase Cloud Messaging:
///
///  * `daily_reminders` topic → three scheduled Cloud Functions
///    (sendMorningReminder / Afternoon / Evening) at 09:00 / 14:00 /
///    20:00 Asia/Riyadh.
///  * `community_events` topic → resetGlobalCounter (after zeroing the
///    shards) and checkMilestone (when the live total crosses 1M).
///
/// Why FCM rather than the previous flutter_local_notifications + on-
/// device AlarmManager schedules: many OEM battery savers
/// (Realme/Xiaomi/Huawei/etc.) silently force-stop the app and cancel
/// its alarms, so daily reminders never fired on those phones. FCM
/// rides on Google Play Services which is whitelisted system-wide,
/// so messages get through regardless of how aggressive the
/// device's battery manager is.
///
/// flutter_local_notifications is still around — it owns the
/// notification *channel* and displays FCM messages that arrive while
/// the app is in the foreground (Android by design suppresses the
/// FCM-system auto-display in that case).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // Must match _fcm.ts on the server.
  static const _channelId = 'salawat_reminders';
  static const _channelName = 'تذكير الصلاة على النبي';
  static const _channelDesc = 'تذكيرات يومية وتنبيهات التحديات';
  static const _topicDaily = 'daily_reminders';
  static const _topicEvents = 'community_events';

  Future<void> init() async {
    if (_initialized) return;
    try {
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        // Tap handler for foreground-displayed notifications. Cold-start
        // taps relaunch MainActivity via FCM's default content intent;
        // this hook is the seam for future payload-based routing.
        onDidReceiveNotificationResponse: _onTap,
      );

      final androidImpl = _local.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Proactively create the channel so the very first FCM message
      // (which may arrive before any foreground display call) has
      // somewhere to land with the right importance/look.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
      // Android 13+ runtime permission for both local channel display
      // and FCM. No-op on older Android versions.
      await androidImpl?.requestNotificationsPermission();
      await FirebaseMessaging.instance.requestPermission();

      // Subscribe to the two topics the server sends to. Idempotent —
      // FCM dedupes subscription requests per device.
      await FirebaseMessaging.instance.subscribeToTopic(_topicDaily);
      await FirebaseMessaging.instance.subscribeToTopic(_topicEvents);

      // Foreground delivery handler: Android won't auto-display
      // notification-type messages while we're on top, so we re-emit
      // them through the local plugin.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      _initialized = true;
    } catch (e, st) {
      debugPrint('[notif] init FAILED: $e\n$st');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage msg) async {
    final notif = msg.notification;
    if (notif == null) return; // data-only messages aren't auto-displayed
    await _local.show(
      msg.hashCode,
      notif.title ?? 'صلوا عليه',
      notif.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'notification_icon',
          largeIcon: DrawableResourceAndroidBitmap('app_logo'),
        ),
      ),
    );
  }

  /// Tap handler for the foreground-displayed (re-emitted) notifications.
  /// Empty hook for future deep-link routing.
  void _onTap(NotificationResponse response) {}
}
