import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

const NUM_SHARDS = 10;
const MAX_DELTA_PER_CALL = 1000;
const IDEM_TTL_HOURS = 24;

interface IncrementRequest {
  delta: number;
  clientRequestId: string;
  clientTs?: string;
}

interface IncrementResponse {
  newTotal: number;
}

/**
 * Single hot endpoint for the entire app. The client batches taps locally
 * and calls this with the delta every ~2.5 seconds.
 *
 * Guarantees:
 *  - Authenticated (anonymous Firebase user is fine).
 *  - Idempotent — safe to retry with the same clientRequestId.
 *  - Sharded global counter (sidesteps Firestore's 1 write/sec/doc throttle).
 *  - Atomic across global / lifetime / daily / user counters.
 */
export const incrementCount = onCall<IncrementRequest, Promise<IncrementResponse>>(
  // maxInstances kept low to fit the default per-region CPU quota that new
  // Blaze projects start with (~20K vCPU-seconds). Each Gen 2 instance can
  // handle ~80 concurrent requests, so 10 is plenty for ~1000 DAU. Bump
  // later if needed and the project's quota has grown.
  { region: 'us-central1', maxInstances: 10 },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError('unauthenticated', 'Sign-in required');
    }

    const { delta, clientRequestId } = request.data;
    if (typeof delta !== 'number' || !Number.isInteger(delta)) {
      throw new HttpsError('invalid-argument', 'delta must be an integer');
    }
    if (delta < 1 || delta > MAX_DELTA_PER_CALL) {
      throw new HttpsError(
        'invalid-argument',
        `delta must be between 1 and ${MAX_DELTA_PER_CALL}`,
      );
    }
    if (typeof clientRequestId !== 'string' || clientRequestId.length < 8) {
      throw new HttpsError('invalid-argument', 'clientRequestId is required');
    }

    const db = getFirestore();
    const idemRef = db.doc(`idempotency/${clientRequestId}`);

    // --- Idempotency: if we've already processed this request, return cached.
    const idemSnap = await idemRef.get();
    if (idemSnap.exists) {
      const cached = idemSnap.data();
      if (cached?.uid !== uid) {
        // Same UUID from a different user — reject as misuse, don't leak data.
        throw new HttpsError('permission-denied', 'Request id mismatch');
      }
      return { newTotal: cached?.newTotal ?? 0 };
    }

    // --- Read current displayName to denormalise into leaderboard docs.
    const userRef = db.doc(`users/${uid}`);
    const userSnap = await userRef.get();
    const displayName =
      (userSnap.exists ? userSnap.data()?.displayName : null) ?? 'Anonymous';

    const shardId = Math.floor(Math.random() * NUM_SHARDS);
    const today = todayUtcDateString();
    const expiresAt = new Date(Date.now() + IDEM_TTL_HOURS * 3_600_000);

    // --- Single batch: 5 writes, atomic.
    const batch = db.batch();
    batch.set(
      db.doc(`globalShards/${shardId}`),
      { count: FieldValue.increment(delta) },
      { merge: true },
    );
    batch.set(
      db.doc(`leaderboardLifetime/${uid}`),
      {
        name: displayName,
        count: FieldValue.increment(delta),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    batch.set(
      db.doc(`leaderboardDaily/${today}/users/${uid}`),
      {
        name: displayName,
        count: FieldValue.increment(delta),
      },
      { merge: true },
    );
    batch.set(
      userRef,
      {
        totalCount: FieldValue.increment(delta),
        lastTapAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    batch.set(idemRef, {
      uid,
      delta,
      processedAt: FieldValue.serverTimestamp(),
      expiresAt,
    });
    await batch.commit();

    // --- Compute the new user total for the response.
    const updatedUserSnap = await userRef.get();
    const newTotal = (updatedUserSnap.data()?.totalCount as number | undefined) ?? delta;

    // Cache for retries.
    await idemRef.update({ newTotal });

    return { newTotal };
  },
);

function todayUtcDateString(): string {
  const d = new Date();
  const yyyy = d.getUTCFullYear();
  const mm = String(d.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(d.getUTCDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}
