import { initializeApp } from 'firebase-admin/app';

initializeApp();

export { incrementCount } from './incrementCount';
export { resetGlobalCounter } from './resetGlobalCounter';
export { cleanupOldData } from './cleanupOldData';
export {
  sendMorningReminder,
  sendAfternoonReminder,
  sendEveningReminder,
} from './sendDailyReminders';
export { checkMilestone } from './checkMilestone';
