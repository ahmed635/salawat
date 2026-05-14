import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const NUM_SHARDS = 10;

/**
 * Daily 00:00 UTC pivot. Atomically:
 *   1. Reads today's `globalShards/{0..9}` totals.
 *   2. Adds the day's sum to `lifetimeBank/total.count` (the running
 *      all-time community total since launch).
 *   3. Zeroes all `globalShards` for the new day.
 *
 * Because `incrementCount` no longer maintains a separate
 * `globalLifetimeShards` collection (saving 1 write per tap), this
 * function is the sole writer of the lifetime accumulator. Doing it all
 * in one transaction means we can't lose taps to a partial reset — every
 * tap that landed before midnight is either still in `globalShards`
 * (waiting to be banked) or already added to `lifetimeBank/total`.
 *
 * Region must match `incrementCount` to keep deploys in one place.
 */
export const resetGlobalCounter = onSchedule(
  {
    // 00:00 Asia/Riyadh (UTC+3 fixed). Matches local midnight for Saudi
    // Arabia and is within an hour of midnight for Egypt year-round.
    schedule: '0 0 * * *',
    timeZone: 'Asia/Riyadh',
    region: 'us-central1',
  },
  async () => {
    const db = getFirestore();
    const lifetimeBankRef = db.doc('lifetimeBank/total');
    const shardRefs = Array.from({ length: NUM_SHARDS }, (_, i) =>
      db.doc(`globalShards/${i}`),
    );

    await db.runTransaction(async (tx) => {
      // All reads must come before any writes in a Firestore transaction.
      const shardSnaps = await Promise.all(shardRefs.map((ref) => tx.get(ref)));

      let dailyTotal = 0;
      for (const snap of shardSnaps) {
        dailyTotal += (snap.data()?.count as number | undefined) ?? 0;
      }

      if (dailyTotal > 0) {
        tx.set(
          lifetimeBankRef,
          {
            count: FieldValue.increment(dailyTotal),
            updatedAt: FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      for (const ref of shardRefs) {
        tx.set(ref, { count: 0 }, { merge: true });
      }
    });
  },
);
