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
  ok: true;
}

/**
 * Single hot endpoint for the entire app. The client batches taps locally
 * and calls this every ~5 seconds.
 *
 * Per-call writes (3, atomic):
 *  1. `globalShards/{shardId}` — today's sharded community counter, zeroed
 *     at UTC midnight by `resetGlobalCounter` (which also rolls the day's
 *     total into `lifetimeBank/total` before zeroing).
 *  2. `leaderboardLifetime/{uid}` — per-user lifetime row. Sole source of
 *     truth for the user's lifetime count; the redundant `users.totalCount`
 *     mirror was retired to save writes.
 *  3. `idempotency/{clientRequestId}` — replay guard with a 24h TTL.
 *
 * The collections previously written per-call but dropped:
 *  - `leaderboardDaily/{day}/users/{uid}` — unused, also reaped nightly
 *    by `cleanupOldData`.
 *  - `globalLifetimeShards/{shardId}` — replaced by the midnight roll-up
 *    into `lifetimeBank/total`.
 *  - `users/{uid}` mirror — `leaderboardLifetime/{uid}.count` already
 *    carries the same data.
 */
export const incrementCount = onCall<IncrementRequest, Promise<IncrementResponse>>(
  {
    region: 'us-central1',
    maxInstances: 10,
    // Reject calls without a valid Firebase App Check token. Pairs with
    // the client-side FirebaseAppCheck.instance.activate(...) in main.dart.
    // Stops the leaked-Web-API-key abuse vector (anyone who pulls the key
    // out of the APK can't drive the global counter from curl).
    enforceAppCheck: true,
  },
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

    // --- Idempotency check.
    const idemSnap = await idemRef.get();
    if (idemSnap.exists) {
      const cached = idemSnap.data();
      if (cached?.uid !== uid) {
        // Same UUID from a different user — reject as misuse, don't leak data.
        throw new HttpsError('permission-denied', 'Request id mismatch');
      }
      return { ok: true };
    }

    // --- Read displayName for leaderboard denormalisation.
    const userRef = db.doc(`users/${uid}`);
    const userSnap = await userRef.get();
    const displayName =
      (userSnap.exists ? userSnap.data()?.displayName : null) ?? 'Anonymous';

    const shardId = Math.floor(Math.random() * NUM_SHARDS);
    const expiresAt = new Date(Date.now() + IDEM_TTL_HOURS * 3_600_000);

    // --- Atomic batch: 3 writes.
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
    batch.set(idemRef, {
      uid,
      delta,
      processedAt: FieldValue.serverTimestamp(),
      expiresAt,
    });
    await batch.commit();

    return { ok: true };
  },
);
