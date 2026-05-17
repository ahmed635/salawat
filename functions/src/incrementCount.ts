import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';

import { todayInResetTz } from './_dates';

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
 * Per-call writes (4, atomic):
 *  1. `globalShards/{shardId}` — today's sharded community counter, zeroed
 *     at 00:00 Asia/Riyadh by `resetGlobalCounter` (which also rolls the
 *     day's total into `lifetimeBank/total` before zeroing).
 *  2. `leaderboardLifetime/{uid}` — per-user lifetime row. Drives badge
 *     achievements on the profile screen and the "since launch" total.
 *  3. `leaderboardDaily/{todayRiyadh}/users/{uid}` — per-user row for
 *     the live daily competition shown on the leaderboard. The old day's
 *     subcollection is reaped by `cleanupOldData` at midnight.
 *  4. `idempotency/{clientRequestId}` — replay guard with a 24h TTL.
 *
 * `globalLifetimeShards` and `users.totalCount` were retired in earlier
 * passes — the former replaced by `lifetimeBank/total`, the latter
 * redundant with `leaderboardLifetime/{uid}.count`.
 */
export const incrementCount = onCall<IncrementRequest, Promise<IncrementResponse>>(
  {
    region: 'us-central1',
    maxInstances: 10,
    // App Check enforcement is OFF until we ship a release keystore with
    // its SHA-256 fingerprints registered with Firebase, and Play
    // Integrity confirmed working in production. With enforce=true and
    // Play Integrity not yet configured, release-build clients can't
    // produce a valid token and every incrementCount call gets rejected
    // with UNAUTHENTICATED. Re-flip to `true` once Play Integrity is
    // attesting tokens for the release-signed app. The client side
    // (main.dart) already initialises FirebaseAppCheck.activate(...);
    // its tokens are accepted but not required yet.
    enforceAppCheck: false,
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
    const today = todayInResetTz();

    // --- Atomic batch: 4 writes.
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
