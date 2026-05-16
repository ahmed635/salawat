import { onSchedule } from 'firebase-functions/v2/scheduler';

import { sendToTopic, TOPIC_DAILY_REMINDERS } from './_fcm';

/**
 * Three daily "لا تنسي الصلاة على النبي ﷺ" reminders, fanned out via FCM
 * to every device subscribed to `daily_reminders`. Cron uses Asia/Riyadh
 * so Saudi users see them at exactly local 09:00 / 14:00 / 20:00;
 * Egypt users see the same instant which is roughly their local clock
 * (within 1h depending on DST). All other timezones receive at whatever
 * their offset places these absolute moments — accepted trade-off vs the
 * full per-user-timezone fan-out fanciness.
 */

const TITLE = 'صلوا عليه';
const BODY = 'لا تنسي الصلاة على النبي ﷺ';

const baseOptions = {
  timeZone: 'Asia/Riyadh',
  region: 'us-central1',
} as const;

export const sendMorningReminder = onSchedule(
  { schedule: '0 9 * * *', ...baseOptions },
  async () => {
    await sendToTopic(TOPIC_DAILY_REMINDERS, TITLE, BODY);
  },
);

export const sendAfternoonReminder = onSchedule(
  { schedule: '0 14 * * *', ...baseOptions },
  async () => {
    await sendToTopic(TOPIC_DAILY_REMINDERS, TITLE, BODY);
  },
);

export const sendEveningReminder = onSchedule(
  { schedule: '0 20 * * *', ...baseOptions },
  async () => {
    await sendToTopic(TOPIC_DAILY_REMINDERS, TITLE, BODY);
  },
);
