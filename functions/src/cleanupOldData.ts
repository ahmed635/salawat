import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore } from 'firebase-admin/firestore';

import { todayInResetTz } from './_dates';

/**
 * Daily janitor.
 *
 * Removes stale `leaderboardDaily/<date>` documents (and their `users/`
 * subcollections) for every date before today UTC. Nothing in the app
 * reads historical daily leaderboards — they're written once per tap and
 * become orphan data the moment the date rolls over.
 *
 * `idempotency/*` is intentionally NOT handled here. Those docs carry an
 * `expiresAt` field set 24h ahead of `processedAt` in `incrementCount`, and
 * are reaped continuously by a Firestore native TTL policy on that field
 * (one-time gcloud config — see README/setup notes). TTL is cheaper and
 * deletes throughout the day instead of in a single nightly burst.
 *
 * Runs in the same UTC slot as `resetGlobalCounter`; the two touch
 * disjoint collections so there's no contention.
 */
export const cleanupOldData = onSchedule(
  {
    // Run at 00:00 Asia/Riyadh, same instant as resetGlobalCounter.
    schedule: '0 0 * * *',
    timeZone: 'Asia/Riyadh',
    region: 'us-central1',
    // Plenty of headroom for `recursiveDelete` on multi-thousand-user
    // subcollections. Default 60s would cut us off in a large month.
    timeoutSeconds: 540,
  },
  async () => {
    const db = getFirestore();
    const today = todayInResetTz();

    const dailyDocs = await db.collection('leaderboardDaily').listDocuments();
    let removed = 0;
    for (const docRef of dailyDocs) {
      // The doc ID is a yyyy-MM-dd string in the reset timezone, so
      // lexicographic comparison matches chronological order. Anything
      // strictly before today gets wiped, including its `users/`
      // subcollection.
      if (docRef.id < today) {
        await db.recursiveDelete(docRef);
        removed += 1;
      }
    }
    console.log(
      `cleanupOldData: removed ${removed} stale daily leaderboard(s) before ${today}`,
    );
  },
);
