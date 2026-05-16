import { getMessaging, Message } from 'firebase-admin/messaging';

/**
 * Shared FCM helpers. Every notification the app shows is now delivered
 * via Cloud Messaging (server → topic → device), not via on-device
 * scheduled alarms. This dodges the OEM battery-saver kill problem
 * (Realme/Xiaomi/Huawei etc.) that broke flutter_local_notifications.
 */

export const TOPIC_DAILY_REMINDERS = 'daily_reminders';
export const TOPIC_COMMUNITY_EVENTS = 'community_events';

/// Must match the Android channel id the client creates in
/// `NotificationService.init`. FCM messages target this channel so they
/// render with the same look/feel (large icon, channel-level importance,
/// audio/vibration) as the old locally-scheduled notifications did.
const CHANNEL_ID = 'salawat_reminders';

export async function sendToTopic(
  topic: string,
  title: string,
  body: string,
): Promise<string> {
  const msg: Message = {
    topic,
    // "notification" payload — Android auto-displays this when the app is
    // in background or terminated. When the app is in foreground we
    // handle it via FirebaseMessaging.onMessage and re-display with
    // flutter_local_notifications (Android by design doesn't auto-show
    // a notification message while the app owns the screen).
    notification: { title, body },
    android: {
      priority: 'high',
      notification: {
        channelId: CHANNEL_ID,
        icon: 'notification_icon',
        defaultSound: true,
        defaultVibrateTimings: true,
      },
    },
  };
  return getMessaging().send(msg);
}
