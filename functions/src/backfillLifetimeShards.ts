import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const NUM_SHARDS = 10;

/**
 * One-shot seeder for `globalLifetimeShards/{0..9}`. Sums the existing
 * `leaderboardLifetime/*.count` (which is the historical lifetime total per
 * user — accumulated from day one) and writes the grand total into shard 0.
 *
 * Idempotent: writes a marker doc at `_meta/lifetimeShardsSeeded` on first
 * successful run; subsequent calls short-circuit. Safe to invoke from any
 * authenticated client — the mobile app fires it once per fresh install,
 * the server marker collapses concurrent calls.
 */
export const backfillLifetimeShards = onCall(
  { region: 'us-central1' },
  async (request) => {
    if (!request.auth?.uid) {
      throw new HttpsError('unauthenticated', 'Sign-in required');
    }
    const db = getFirestore();
    const markerRef = db.doc('_meta/lifetimeShardsSeeded');

    // Use a transaction so two concurrent callers can't both run the sum.
    const result = await db.runTransaction(async (tx) => {
      const marker = await tx.get(markerRef);
      if (marker.exists) {
        return { skipped: true as const };
      }
      // Aggregate sum of every user's lifetime count. With ~1000 users this
      // is a single read; if the user base grows past tens of thousands,
      // switch to a paginated scan.
      const lifetimeSnap = await tx.get(db.collection('leaderboardLifetime'));
      let total = 0;
      lifetimeSnap.forEach((d) => {
        total += (d.data().count as number | undefined) ?? 0;
      });

      for (let i = 0; i < NUM_SHARDS; i++) {
        tx.set(
          db.doc(`globalLifetimeShards/${i}`),
          { count: i === 0 ? total : 0 },
          { merge: true },
        );
      }
      tx.set(markerRef, {
        done: true,
        seededTotal: total,
        seededAt: FieldValue.serverTimestamp(),
      });
      return { seeded: true as const, total };
    });

    return result;
  },
);
