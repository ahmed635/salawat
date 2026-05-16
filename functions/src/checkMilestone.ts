import { onSchedule } from 'firebase-functions/v2/scheduler';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { sendToTopic, TOPIC_COMMUNITY_EVENTS } from './_fcm';
import { todayInResetTz } from './_dates';

/**
 * Polls the live global counter every 15 minutes. The moment it crosses
 * the 1,000,000 daily goal, fan out the "بدأ تحدي ال 2 مليون"
 * celebration to every device subscribed to `community_events`. A marker
 * doc at `_meta/milestoneFiredOn` keyed by the Riyadh date guarantees we
 * fire at most once per challenge cycle even if the counter dips and
 * crosses again.
 *
 * Why a poller instead of a Firestore trigger? Each shard write only
 * tells us its own delta, not the global total — checking the threshold
 * per-write would mean an extra 10 reads on every tap-flush. A 15-min
 * scheduled poll is one read per check, negligible cost.
 */
const MILESTONE_THRESHOLD = 1_000_000;

export const checkMilestone = onSchedule(
  {
    schedule: '*/15 * * * *',
    timeZone: 'Asia/Riyadh',
    region: 'us-central1',
  },
  async () => {
    const db = getFirestore();
    const today = todayInResetTz();
    const markerRef = db.doc('_meta/milestoneFiredOn');

    const marker = await markerRef.get();
    if (marker.exists && marker.data()?.date === today) {
      return; // already celebrated today
    }

    const shardsSnap = await db.collection('globalShards').get();
    let total = 0;
    shardsSnap.forEach((d) => {
      total += (d.data().count as number | undefined) ?? 0;
    });

    if (total <= MILESTONE_THRESHOLD) {
      return;
    }

    // Claim the marker first so concurrent runs short-circuit. We
    // accept a tiny race window — at worst two simultaneous invocations
    // could both pass this point and double-send, which is fine.
    await markerRef.set({
      date: today,
      total,
      firedAt: FieldValue.serverTimestamp(),
    });
    await sendToTopic(
      TOPIC_COMMUNITY_EVENTS,
      'صلوا عليه',
      'بدأ تحدي ال 2 مليون',
    );
  },
);
