/**
 * Date helpers for the "reset" timezone shared across all server functions.
 *
 * The global community counter, the daily leaderboard partition, and the
 * `cleanupOldData` sweep all align with this timezone — they have to
 * agree on what "today" means.
 *
 * Asia/Riyadh is UTC+3 fixed (no DST), which keeps the reset instant
 * stable year-round and lines up exactly with local midnight for users
 * in Saudi Arabia and (in summer) Egypt.
 */
export const RESET_TIMEZONE_OFFSET_HOURS = 3;

export function todayInResetTz(): string {
  const utcNow = Date.now();
  const shifted = new Date(utcNow + RESET_TIMEZONE_OFFSET_HOURS * 3_600_000);
  const yyyy = shifted.getUTCFullYear();
  const mm = String(shifted.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(shifted.getUTCDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}
