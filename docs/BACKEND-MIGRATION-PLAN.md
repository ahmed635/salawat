# Firebase → Spring Boot migration plan

Working document for the question: *should we replace Firebase with a self-hosted Spring backend to cut hosting cost?* Generated from the in-session analysis on 2026-05-18, captures the reasoning, the recommendations, and the order-of-operations for if/when we do this.

This is **not** an instruction to migrate. The first half explains why migration may not be needed; the second half details how to do it well if we decide it is.

---

## 1. Decision criteria — read this first

Migration is only justified at scale. Concrete thresholds:

| Current monthly Firebase bill | Recommendation |
|---|---|
| **< $20/mo** | Don't migrate. Engineering time vastly exceeds savings. |
| **$20–$100/mo** | First try the [cheap optimizations below](#3-cheap-optimisations-to-try-first). If they don't cut the bill enough, plan migration for the next quarter, not this one. |
| **$100–$500/mo** | Migration starts to make sense. Still try optimizations first. |
| **> $500/mo** | Migration recommended. The fixed-cost VPS becomes cheaper in months, not years. |

**Required pre-work:** pull the actual current monthly bill from Firebase Console → Usage and billing, or `gcloud billing budgets list`. The plan below is shaped by what's currently deployed, but actual costs depend on traffic which only you can measure.

**Order-of-magnitude estimate at 1M+ taps/day:**

| Cost line | Daily | Monthly |
|---|---|---|
| Firestore reads (client polling globalShards) | $1–3 | $30–100 |
| Firestore reads (leaderboard + my-rank aggregations) | $0.50–1 | $15–30 |
| Firestore writes (incrementCount, 4 docs/call) | $0.20–0.50 | $6–15 |
| Cloud Functions invocations + compute | $0.05–0.10 | $1.50–3 |
| Cloud Scheduler / FCM / Auth | ~$0 | ~$0 |
| **Total est.** | **~$2–5/day** | **~$60–150/mo** |

Reads dominate. That's where optimisation focus should go first.

---

## 2. Current Firebase service inventory

What's deployed today and what would need to be replaced:

| Service | Used for | Migration story |
|---|---|---|
| **Cloud Firestore** | Counters, leaderboards, idempotency, users, metadata | → Postgres (single source of truth) |
| **Cloud Functions** (4 deployed) | `incrementCount`, `resetGlobalCounter`, `cleanupOldData`, `checkMilestone`, 3× `send*Reminder` | → Spring REST endpoints + `@Scheduled` methods |
| **Cloud Scheduler** | Cron triggers for the 6 scheduled functions | → Spring `@Scheduled(cron = …, zone = "Asia/Riyadh")` |
| **Firebase Auth** (anonymous) | Per-device UID for leaderboard rows | → Custom JWT issued from Spring `/auth/anonymous` |
| **Cloud Messaging (FCM)** | Push notifications to topics `daily_reminders`, `community_events` | **Keep.** Free. Spring calls FCM Admin SDK. |
| **App Check** | Currently activated client-side, server enforcement **off** (because release keystore not generated yet) | → Drop entirely. Replace with rate-limiting at the Spring layer. |
| **Cloud Storage** | Not used | n/a |

---

## 3. Cheap optimisations to try first

Before any rewrite. Could cut bill 5–10× without an architecture change.

### 3.1 Bump client polling interval back

`mobile/lib/data/global_count_repository.dart` currently has `_refreshInterval = Duration(minutes: 1)`. Was 5 min before the user asked for 1. Reverting to 3–5 min saves 3–5× on global-counter reads, which is the biggest line item.

### 3.2 Switch the leaderboard from live snapshots to one-shot + pull-to-refresh

`leaderboardTopProvider` uses Firestore `.snapshots()`, which charges per change emission. A `.get()` on screen open + manual refresh button gives steady-state zero reads while the screen is idle.

### 3.3 Aggregate `globalShards` server-side

Add a `globalAggregated/current` doc updated by a `@Schedule('*/5 * * * *')` function that sums the 10 shards. Clients read **one** doc instead of streaming 10. Cuts client polling reads 10×.

### 3.4 Cache lifetime sum

`lifetimeBank/total` + `sum(globalShards)` is computed on every lifetime fetch. Cache the bank value client-side; only refetch globalShards. Already done; just verify.

### 3.5 Tighter App Check enforcement

Once a release keystore is generated and Play Integrity is wired, flip `enforceAppCheck: true` back on. Stops anyone with a leaked Web API key from hammering the function.

**Estimated impact of all five:** **5–10× lower Firestore read cost**, no client refactor, ~1–2 days of work. Try this first.

---

## 4. If migrating — recommended stack

Pick **Spring Boot 3.x on Java 21**. The user already knows Spring.

| Layer | Choice | Notes |
|---|---|---|
| Runtime | Spring Boot 3.x, Java 21 | Virtual threads for high-concurrency counter writes |
| DB | **Postgres 16** | A single row + `UPDATE ... SET n = n + ?` handles 5–10K writes/sec on modest hardware. No sharding needed at the scale this app reaches. |
| Cache (optional) | Redis (Upstash free tier or self-hosted) | Idempotency keys + hot counter cache. Day-one optional. |
| Migrations | Flyway | Versioned SQL files |
| Auth | Server-issued JWT via `jjwt` | Anonymous flow: POST `/auth/anonymous` → server creates `users` row, returns JWT |
| REST | Spring MVC (sync) | WebFlux is overkill until 10K+ QPS |
| Push | **Keep FCM** via Firebase Admin SDK Java | Free, well-engineered |
| Hosting (cheapest) | **Hetzner CX21** (2 vCPU, 4 GB) ≈ €5.83/mo (~$6) | Self-host Postgres on the same box. Handles thousands of concurrent users. |
| Hosting (managed) | Fly.io / Railway / Render / Cloud Run + Cloud SQL | ~$20–30/mo. Worth it for a solo dev. |
| Reverse proxy + SSL | Caddy | One-line config, auto Let's Encrypt |
| Backups | `pg_dump` cron → Backblaze B2 | ~$0.50/mo for storage |
| Monitoring | UptimeRobot (free) + Spring Actuator | Don't over-engineer day one |

**Total flat cost target:** ~$6–10/mo (Hetzner) or ~$25/mo (managed PaaS).

---

## 5. Data model translation

Postgres schema, more or less direct from the Firestore model. Riyadh-date partitioning collapses into a regular column.

```sql
CREATE TABLE users (
  id           UUID PRIMARY KEY,
  display_name TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_tap_at  TIMESTAMPTZ
);

-- Single-row counter — Postgres row-level locks handle contention.
CREATE TABLE global_counter (
  id              INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  daily_total     BIGINT NOT NULL DEFAULT 0,
  lifetime_total  BIGINT NOT NULL DEFAULT 0,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE leaderboard_lifetime (
  user_id UUID PRIMARY KEY REFERENCES users(id),
  count   BIGINT NOT NULL DEFAULT 0
);
CREATE INDEX ON leaderboard_lifetime (count DESC);

CREATE TABLE leaderboard_daily (
  user_id     UUID NOT NULL REFERENCES users(id),
  riyadh_date DATE NOT NULL,
  count       BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, riyadh_date)
);
CREATE INDEX ON leaderboard_daily (riyadh_date, count DESC);

CREATE TABLE idempotency (
  req_id     TEXT PRIMARY KEY,
  user_id    UUID NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX ON idempotency (expires_at);  -- for daily cleanup
```

### `incrementCount` becomes:

```java
@PostMapping("/api/v1/counter/increment")
@Transactional
public ResponseEntity<Void> increment(@RequestBody IncrementRequest req, @AuthUser User u) {
    if (idempotencyRepo.existsById(req.clientRequestId)) {
        return ResponseEntity.ok().build();
    }
    idempotencyRepo.insert(req.clientRequestId, u.getId(), Instant.now().plus(24, HOURS));

    jdbc.update(
        "UPDATE global_counter SET daily_total = daily_total + ?, " +
        "  lifetime_total = lifetime_total + ?, updated_at = now() WHERE id = 1",
        req.delta, req.delta);

    jdbc.update(
        "INSERT INTO leaderboard_lifetime (user_id, count) VALUES (?, ?) " +
        "ON CONFLICT (user_id) DO UPDATE SET count = leaderboard_lifetime.count + EXCLUDED.count",
        u.getId(), req.delta);

    jdbc.update(
        "INSERT INTO leaderboard_daily (user_id, riyadh_date, count) VALUES (?, ?, ?) " +
        "ON CONFLICT (user_id, riyadh_date) DO UPDATE SET count = leaderboard_daily.count + EXCLUDED.count",
        u.getId(), todayRiyadh(), req.delta);

    return ResponseEntity.ok().build();
}
```

Three statements, one transaction. Postgres handles this at thousands of QPS on a $6 VPS.

### Scheduled jobs become `@Scheduled`:

```java
@Component
@EnableScheduling
public class DailyJobs {

    @Scheduled(cron = "0 0 0 * * *", zone = "Asia/Riyadh")
    public void midnightReset() {
        jdbc.update(
            "UPDATE global_counter SET lifetime_total = lifetime_total + daily_total, " +
            "daily_total = 0 WHERE id = 1");
        jdbc.update("DELETE FROM leaderboard_daily WHERE riyadh_date < CURRENT_DATE");
        fcm.sendToTopic("community_events", "صلوا عليه", "ها قد بدأ تحدي جديد");
    }

    @Scheduled(cron = "0 0 9,14,20 * * *", zone = "Asia/Riyadh")
    public void dailyReminder() {
        fcm.sendToTopic("daily_reminders", "صلوا عليه", "لا تنسي الصلاة على النبي ﷺ");
    }

    @Scheduled(fixedRate = 900_000) // 15 min
    public void checkMilestone() {
        Long total = jdbc.queryForObject(
            "SELECT daily_total FROM global_counter WHERE id = 1", Long.class);
        String today = LocalDate.now(ZoneId.of("Asia/Riyadh")).toString();
        if (total > 1_000_000 && !milestoneFired(today)) {
            markFired(today);
            fcm.sendToTopic("community_events", "صلوا عليه", "بدأ تحدي ال 2 مليون");
        }
    }

    @Scheduled(cron = "0 0 * * * *") // hourly cleanup of expired idempotency
    public void reapIdempotency() {
        jdbc.update("DELETE FROM idempotency WHERE expires_at < now()");
    }
}
```

---

## 6. Endpoint mapping

| Current (Firebase) | New (Spring) | Notes |
|---|---|---|
| `incrementCount` callable | `POST /api/v1/counter/increment` | Body unchanged: `{delta, clientRequestId}`. Auth via JWT in `Authorization: Bearer`. |
| Firestore `globalShards.snapshots()` | `GET /api/v1/counter/global` | Returns `{count, lifetimeCount}`. Client polls (same 1-min or 5-min cadence). |
| Firestore `leaderboardDaily/{today}/users` | `GET /api/v1/leaderboard/daily?limit=50` | Server resolves today's Riyadh date internally. |
| `count()` aggregation for myRank | `GET /api/v1/leaderboard/my-rank` | Returns `{rank, count, name}`. Server-side throttle still applies (cache per-user 30s). |
| FirebaseAuth anonymous signIn | `POST /api/v1/auth/anonymous` | Returns `{userId, jwt}`. Client persists jwt to secure storage. |
| `users/{uid}.displayName` write | `PATCH /api/v1/users/me` | Body: `{displayName}`. |
| `resetGlobalCounter` / `cleanupOldData` / `send*Reminder` / `checkMilestone` | `@Scheduled` in Spring | Server-internal, no HTTP. |
| FCM topics | **unchanged** | Spring calls `FirebaseMessaging.getInstance().send(...)` server-side. |

---

## 7. Client refactor scope

| Today (Firebase) | Tomorrow (Spring) | Effort |
|---|---|---|
| `cloud_firestore` reads | `dio` or `http` package | Medium |
| `cloud_functions` callable | Same HTTP package | Easy |
| `firebase_auth` anonymous | Custom JWT + `flutter_secure_storage` | Medium |
| `firebase_app_check` | Drop entirely (add server-side rate limiting instead) | Trivial |
| `firebase_messaging` | **Keep as-is** — Spring sends via FCM Admin SDK | Trivial |
| Firestore real-time listeners | Periodic HTTP polls (same UX as today) | Easy |
| Firestore offline cache | Reimplement (e.g., `hive` for leaderboard last-known state) | Medium — biggest UX risk |

Rough effort: **~40% of client Dart code touches Firebase**. Realistic estimate: **2–3 weeks of focused work** to migrate, including testing on a real device.

### Files that will change

```
mobile/lib/
  data/
    auth_repository.dart          ← swap FirebaseAuth → JWT + httpx
    counter_sync.dart             ← swap Cloud Functions → REST
    firestore_paths.dart          ← delete entirely
    global_count_repository.dart  ← swap snapshots → HTTP polls
    leaderboard_repository.dart   ← swap snapshots → HTTP polls
    user_repository.dart          ← swap Firestore writes → REST
  core/
    notifications.dart            ← unchanged (FCM stays)
    daily_reset.dart              ← unchanged
    counter_controller.dart       ← unchanged
  app.dart                        ← swap ensureSignedInProvider
  main.dart                       ← drop Firebase.initializeApp
  firebase_options.dart           ← delete

functions/                        ← delete entire directory after Phase 4
```

---

## 8. Phased migration plan (zero-downtime)

Don't hard-cut. 4 phases over ~2 months part-time:

### Phase 1 — Stand up Spring in parallel (1–2 weeks)
- Provision Hetzner CX21 + Postgres + Caddy.
- Implement all endpoints + schema + scheduled jobs.
- Deploy to staging at e.g. `api.salawat.app`.
- **No client changes yet.** Spring backend is operational but unused.

### Phase 2 — Dual-write from Firebase (1 week)
- Modify each Cloud Function to **also call the Spring backend** after its Firestore write succeeds. Use a Spring "ingest" endpoint that accepts deltas.
- Postgres mirrors Firestore. Verify daily with a diff query: `SELECT user_id, lifetime_count FROM postgres_leaderboard_lifetime` vs Firestore export.
- If mirror is consistent for 1 week, proceed.

### Phase 3 — Reads from Spring (1 week)
- Flutter app: switch leaderboard + global-counter reads from Firestore to Spring HTTP endpoints. Keep `incrementCount` calls going to the Cloud Function.
- **This is where the cost drops sharply** — read traffic is the dominant Firestore line.
- Push new APK / app bundle through Play Store internal testing.

### Phase 4 — Writes to Spring, decommission Firebase (1 week + 2 weeks tail)
- Flutter app: switch `incrementCount` calls to Spring endpoint.
- Wait 1–2 weeks for old-client users to update via Play Store auto-update.
- Turn off Cloud Functions one-by-one (start with the schedulers; finally `incrementCount` once usage drops near zero).
- Export final Firestore snapshot, archive to B2, delete Firestore database.

**Kept:** Firebase Auth (optional — could also be replaced; depends on whether anonymous UIDs need to remain stable across the cutover), FCM.

---

## 9. Operational tax — be honest about this

The flat cost of the VPS comes with ongoing work Firebase did for free. Budget for this:

| Concern | Day-one approach |
|---|---|
| **Backups** | Nightly `pg_dump` cron → encrypted upload to Backblaze B2. Weekly test restore. Without this, the first disk failure is fatal. |
| **Monitoring** | UptimeRobot pinging `/health` every minute; email alert on 2 consecutive failures. Spring Actuator for liveness/readiness. |
| **Security updates** | `unattended-upgrades` for system; manual `apt upgrade` weekly. Cloudflare in front for DDoS / basic WAF. |
| **Deploys** | GitHub Actions → SSH → `docker compose pull && docker compose up -d`. ~1 day to set up. |
| **Logs** | journald + `docker compose logs` to start. Add Loki + Grafana when you actually need to query them historically. |
| **Disaster recovery** | Document the rebuild from scratch: provision VPS → install Docker → restore latest pg_dump → done in <2 hours. Test this once. |
| **On-call** | **You.** If the server goes down at 3 AM you're the one waking up. Firebase had this baked in. |

Honestly factor this against your time. If you value your weekends, a managed Postgres ($15–25/mo) + Cloud Run ($5–10/mo) trades a bit of money for substantially less ops burden.

---

## 10. Bottom-line recommendation

1. **Measure first.** Get the actual current monthly bill. If under $50/mo, none of this matters yet.
2. **Try the polling-interval + leaderboard fetch optimisations.** ~1 day of work, could solve the problem entirely.
3. **If migration is justified**: Hetzner CX21 + self-hosted Postgres 16 + Spring Boot 3 + keep FCM. ~$6/mo flat. ~2 months part-time with the 4-phase plan.
4. **Don't hard-cut over a weekend.** The dual-write phase is what makes the migration safe.
5. **Plan the operational tax.** Backups + monitoring + on-call are not optional.

---

## 11. Files to consult when starting work

- `functions/src/incrementCount.ts` — the hot-path logic to port
- `functions/src/resetGlobalCounter.ts`, `cleanupOldData.ts`, `sendDailyReminders.ts`, `checkMilestone.ts` — scheduled job logic to port
- `functions/src/_fcm.ts` — FCM patterns; Spring equivalent uses `FirebaseMessaging.getInstance().send(...)` from `firebase-admin` Java SDK
- `firestore.rules` — translates to Spring `@PreAuthorize` annotations
- `mobile/lib/data/*.dart` — every file under `data/` is a candidate for rewrite
- `mobile/lib/core/notifications.dart` — stays untouched; FCM subscription survives the migration

---

*Generated 2026-05-18. Refresh this document whenever the Firebase usage profile changes significantly, or after any of the "cheap optimisations" land.*
