# Salawat Counter App — Architecture

> **⚠️ Superseded.** This doc describes a **self-hosted Node + Redis + Postgres** backend. The project has since pivoted to **Firebase**, and an existing React + Firebase prototype is being ported to Flutter. The active plan is in [`FLUTTER-CONVERSION.md`](./FLUTTER-CONVERSION.md). This file is kept for reference — many of the principles (offline-first counter, sharded counters, tier display, spiritual considerations in §9) still apply to the Firebase port.

A Flutter mobile app for counting Salawat (prayers upon the Prophet ﷺ), backed by a self-hosted Node.js stack. Designed to scale from 1 to 1M+ users without re-architecting.

---

## 1. Goals & Non-Goals

**Goals**
- One-tap counter, fully usable offline (no spinner, no network on the hot path).
- Persistent personal total, syncs across devices.
- Multiple leaderboard views: global, daily, weekly, country, group.
- Community total ("the ummah said X today") prominent on home screen.
- Self-hosted on commodity VPS, predictable cost.
- Sub-200ms perceived latency (counter is local; sync is async).

**Non-goals (v1)**
- Voice recognition counting.
- Audio/video content, social feed, chat.
- Offline leaderboards.
- Multi-language UI beyond Arabic + English.

---

## 2. System Architecture

```
┌────────────────────────────┐
│      Flutter Client        │
│  ┌──────────────────────┐  │
│  │ Hive (local DB)      │  │  every tap → instant local write
│  │  total               │  │
│  │  lastSyncedTotal     │  │
│  │  pendingRequestId    │  │
│  └─────────┬────────────┘  │
│            │  batch every 15s OR on background OR on connectivity restored
└────────────┼───────────────┘
             │ HTTPS + JWT
             ▼
   ┌─────────────────────┐
   │ Cloudflare (free)   │   DDoS, TLS, edge-cache leaderboards
   └─────────┬───────────┘
             ▼
   ┌─────────────────────┐
   │ Caddy (auto-TLS)    │   reverse proxy + load balance
   └─────────┬───────────┘
             ▼
   ┌─────────────────────┐
   │ Node.js + Fastify   │   stateless, horizontally scalable
   │  /v1/count          │
   │  /v1/leaderboard/*  │
   │  /v1/auth/*         │
   └──┬──────────────┬───┘
      │              │
      ▼              ▼
 ┌─────────┐   ┌──────────────┐
 │  Redis  │   │  PostgreSQL  │
 │ hot path│   │   durable    │
 │ counts  │   │   users      │
 │ ZSETs   │   │   daily_*    │
 │ rate    │   │   audit      │
 │ idem    │   │              │
 └────┬────┘   └──────┬───────┘
      │               ▲
      └───────────────┘
       worker: every 5 min
       Redis → Postgres snapshot
```

---

## 3. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Mobile | Flutter 3.x + Dart 3.x | Single codebase, iOS + Android |
| State | Riverpod 2.x | Compile-safe, async-friendly |
| Local DB | Hive 2.x | Fastest tap-write, perfect for counter |
| HTTP | Dio + interceptors | Auth refresh, retry, offline queue |
| Backend | Node.js 22 LTS + Fastify 4.x | 2–3× Express throughput, schema-validated |
| Hot store | Redis 7.x | Sorted Sets = native leaderboards |
| Durable | PostgreSQL 16 | Boring, reliable, free |
| Auth | Firebase Auth (verify JWTs server-side) | Free Google/Apple sign-in, no OAuth code to write, no Firebase data lock-in |
| Reverse proxy | Caddy 2 | Auto-TLS via Let's Encrypt |
| Edge | Cloudflare (free tier) | DDoS protection + cache leaderboard responses |
| Container | Docker + docker-compose | Single-host deploy on day 1 |
| Monitoring | Grafana + Prometheus + Loki | Free, self-hosted |
| Backups | restic → Backblaze B2 | $0.005/GB/month |
| Errors | Sentry (free tier or self-host) | Crash reports |

**Why Firebase Auth with custom backend:** you avoid Firebase's data lock-in but get Google/Apple sign-in for free. Your Node backend uses `firebase-admin` to verify the ID token on each request — that's the only Firebase coupling.

---

## 4. Data Model

### 4.1 Redis (hot path, source of truth at runtime)

| Key | Type | Purpose | TTL |
|---|---|---|---|
| `user:{id}:total` | string (int) | All-time count | none |
| `lb:global` | ZSET | All-time leaderboard, score = count | none |
| `lb:daily:{YYYY-MM-DD}` | ZSET | Today | 60d |
| `lb:weekly:{YYYY-WW}` | ZSET | This week | 1y |
| `lb:country:{ISO}:global` | ZSET | Per-country | none |
| `lb:group:{groupId}` | ZSET | Group internal | none |
| `community:total` | string (int) | Total ummah count, all-time | none |
| `community:total:{YYYY-MM-DD}` | string (int) | Daily community count | 60d |
| `idem:{clientReqId}` | string (json) | Idempotency cache | 24h |
| `rate:{userId}:{minute}` | string (int) | Rate-limit window | 2 min |
| `user:{id}:profile` | hash | display_name, country, avatar_url | 1h |

### 4.2 PostgreSQL (durable, audit, history)

```sql
CREATE TABLE users (
  id              UUID PRIMARY KEY,
  firebase_uid    TEXT UNIQUE,
  display_name    TEXT,
  country_iso     CHAR(2),
  is_anonymous    BOOLEAN NOT NULL DEFAULT TRUE,
  is_visible_lb   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  total_snapshot  BIGINT NOT NULL DEFAULT 0,
  snapshot_at     TIMESTAMPTZ
);
CREATE INDEX idx_users_firebase_uid ON users(firebase_uid);

CREATE TABLE daily_counts (
  user_id  UUID NOT NULL REFERENCES users(id),
  day      DATE NOT NULL,
  count    BIGINT NOT NULL,
  PRIMARY KEY (user_id, day)
);
CREATE INDEX idx_daily_day ON daily_counts(day, count DESC);

CREATE TABLE count_audit (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID NOT NULL,
  delta         INT NOT NULL,
  client_req_id TEXT NOT NULL,
  client_ts     TIMESTAMPTZ,
  server_ts     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  device_id     TEXT,
  ip_hash       TEXT
);
-- partition by month, drop after 90 days
```

### 4.3 Why both Redis and Postgres?

- **Redis** handles every live write. `ZINCRBY` is O(log N), single-digit milliseconds.
- **Postgres** survives Redis crash, gives historical analytics + audit trail.
- **Worker** snapshots Redis → Postgres every 5 min. On Redis cold start, rehydrate from `users.total_snapshot`.

---

## 5. Counter Sync Protocol (Critical)

This is where most apps fail at scale. Read carefully.

### 5.1 Client side (Flutter / Hive)

```dart
class CounterStore {
  int total;             // displayed to user
  int lastSyncedTotal;   // last value the server has accepted
  String? pendingReqId;  // UUID of in-flight request
}

// On tap (instant, no network):
total += 1;
hive.put('counter', store);

// Sync trigger: every 15s OR app backgrounded OR connectivity restored
Future<void> sync() async {
  final delta = total - lastSyncedTotal;
  if (delta == 0) return;
  pendingReqId ??= uuid.v4();

  final res = await api.post('/v1/count', {
    'delta': delta,
    'clientRequestId': pendingReqId,
    'clientTs': DateTime.now().toIso8601String(),
  });

  if (res.ok) {
    lastSyncedTotal = total;   // captured at time of request
    pendingReqId = null;
  }
  // on network error: keep state, retry next tick
}
```

**Invariants:**
- `total` is **monotonic** on the client. Never decreases.
- **One in-flight request at a time per user.** Prevents double-increment.
- **`clientRequestId` reused on retry.** Server dedupes via `idem:{reqId}` key.

### 5.2 Server side

```
POST /v1/count
  body: { delta, clientRequestId, clientTs }
  auth: JWT → userId

  1. Idempotency:
     if SET NX idem:{reqId} ttl=24h fails → return cached response

  2. Rate limit (anti-cheat):
     window = INCR rate:{userId}:{currentMinute}; EXPIRE 120
     if delta > 1000 in single request → 400 (split it)
     if window > 600 in last minute → 429

  3. Apply (single MULTI/EXEC pipeline):
     newTotal = INCRBY user:{userId}:total delta
     ZINCRBY lb:global delta userId
     ZINCRBY lb:daily:{today} delta userId
     ZINCRBY lb:weekly:{week} delta userId
     ZINCRBY lb:country:{iso}:global delta userId
     INCRBY community:total delta
     INCRBY community:total:{today} delta

  4. SET idem:{reqId} {newTotal} ttl=24h

  5. Async-queue: append to count_audit (non-blocking)

  return 200 { newTotal }
```

All Redis operations in one pipeline = 1 round-trip. Throughput on a $13/mo box: thousands of `/count` per second.

### 5.3 Multi-device same user

- Each device has its own `lastSyncedTotal` watermark.
- Server total = sum of all deltas ever sent by all devices.
- On app open: `GET /v1/me` → `serverTotal`. If `total < serverTotal`, set `total = serverTotal` (new device adopts server's view; never loses count, never double-counts).

---

## 6. Auth Flow

```
First launch
  POST /v1/auth/anonymous { deviceId } → JWT
  User counts immediately, no signup gate.

Optional sign-in (later)
  Flutter Firebase SDK → user signs in with Google/Apple
  → POST /v1/auth/link { firebaseIdToken }
  → Backend verifies via firebase-admin, links users.firebase_uid
  → New JWT for the linked user
  → Now the user can sync across devices.
```

Anonymous users **can be on the leaderboard** but display as "Believer #4231" + country flag. Custom display names require sign-in (anti-spam).

---

## 7. API Spec (v1)

| Method | Path | Purpose |
|---|---|---|
| POST | `/v1/auth/anonymous` | Create anon user, return JWT |
| POST | `/v1/auth/link` | Upgrade anon → signed-in (Firebase token) |
| POST | `/v1/auth/refresh` | Refresh JWT |
| GET | `/v1/me` | Profile + total |
| PATCH | `/v1/me` | display_name, country, leaderboard visibility |
| POST | `/v1/count` | Submit delta (the hot endpoint) |
| GET | `/v1/leaderboard/global?limit=100` | Top N global |
| GET | `/v1/leaderboard/daily?date=YYYY-MM-DD&limit=100` | Daily |
| GET | `/v1/leaderboard/country/:iso?limit=100` | Country-specific |
| GET | `/v1/me/rank` | `{ globalRank, dailyRank, percentile, tier }` |
| GET | `/v1/community/totals` | `{ today, allTime }` |
| POST | `/v1/groups` | Create group (masjid, family, friends) |
| POST | `/v1/groups/:id/join` | Join via invite code |
| GET | `/v1/groups/:id/leaderboard` | Group internal leaderboard |

**Cloudflare caches** leaderboard responses with `Cache-Control: public, s-maxage=60`. At 1M users, you serve ~99% of leaderboard reads from edge — your origin barely sees them.

---

## 8. Integrity & Anti-Cheat

People will cheat for ranks. Mitigations in order of impact:

1. **Server-side rate limit:** max ~10 taps/sec sustained, 1000 per request. Above = bot.
2. **Per-IP daily cap on new accounts** to prevent farming.
3. **Sign-in required for global leaderboard** (anonymous users see ranks but don't appear). Google/Apple = real cost to fake an identity.
4. **Anomaly detection (post-hoc):** nightly job flags top 1% with abnormal patterns — counts during sleep hours, perfectly uniform tap intervals (from `count_audit`). Manual review or auto shadow-ban.
5. **Tier display by default:** "Top 1%" instead of "#4,231" — reduces cheating incentive (and is more spiritually appropriate, see §9).

Don't bother with client-side obfuscation. Anyone determined will reverse it. **Server is the only source of truth.**

---

## 9. Spiritual / Ethical Design

This deserves real thought, not a checkbox.

Salawat is sincere worship. Pure global rankings can encourage *riya'* (showing off), which contradicts the act itself. Recommended defaults that honor this:

- **Default to private** — new users opt *into* the global leaderboard, not out.
- **Tier display, not exact rank** — "Top 5% today" rather than "#4,231".
- **Lead with community total** — big number on home screen: "the ummah said X today" — emphasizes collective worship.
- **Group leaderboards as primary** — family, masjid, friend circles. Healthier competition among people who know each other.
- **Anonymous leaderboard names** by default ("Believer #4231" + country flag), opt-in display name.
- **Daily reset emphasis** over all-time — encourages consistency, not accumulation.

Talk to scholars/imams in your target community before launch. The technical scale matters less than getting the tone right.

---

## 10. Scale Roadmap

| Stage | DAU | Architecture | ~Cost/mo |
|---|---|---|---|
| **MVP** | 0–10K | 1× Hetzner CCX13 (4 vCPU / 16GB) running Caddy + Node + Redis + Postgres in Docker | $13 |
| **Growth** | 10K–100K | 2× Node behind Caddy LB, 1× Redis box, 1× Postgres box. Cloudflare in front. | ~$60 |
| **Scale** | 100K–1M | 3+ Node (Docker Swarm or Nomad), managed Redis (Upstash) + Postgres (Neon/Supabase) | $200–500 |
| **Massive** | 1M+ | Per-region Redis read replicas (leaderboards), Postgres primary + replicas, Kafka in front of count writes | $500–2K |

**Bottlenecks in order of arrival:**
1. Postgres connection pool → add **PgBouncer** at ~100K.
2. Single Redis CPU → migrate to **Redis Cluster** at ~500K.
3. Node JSON encoding → switch to Protobuf at ~1M (probably never needed).

---

## 11. Cost Math (sanity check)

Assume 100K DAU, average 100 taps/day, batched every 15s (~6 syncs/day):
- **Writes/sec:** 100K × 6 / 86400 ≈ 7/sec average, ~50/sec peak. Trivial.
- **Storage:** 100K profiles × ~1KB + 100K × 30 days daily_counts × ~50B ≈ 250MB. Trivial.
- **Bandwidth:** ~1KB per sync × 600K/day ≈ 18GB/mo. Trivial.

**The app is bandwidth- and write-light *because of the batching.*** Without batching: 100K × 100 = 10M writes/day to the DB — entirely different problem.

---

## 12. Implementation Phases

| Phase | Scope | Est. |
|---|---|---|
| **1. Local-only counter** | Flutter app, Hive storage, big tap area, today/total display. No backend. Validates UX. | 1 wk |
| **2. Backend skeleton** | Node + Fastify + Redis + Postgres in docker-compose. Anon auth, `/count` with idempotency. Hetzner deploy with Caddy auto-TLS. Flutter syncs deltas. | 1 wk |
| **3. Leaderboards** | ZSET-backed global/daily/weekly/country. `/me/rank` with percentile + tier. Community total on home. | 1 wk |
| **4. Sign-in & multi-device** | Firebase Auth integration, link flow, multi-device correctness tests. | 1 wk |
| **5. Groups** | Create/join via invite code, group leaderboards, group totals. | 1 wk |
| **6. Anti-cheat & polish** | Rate limits, audit log, anomaly job. Cloudflare in front. Monitoring + alerting. App store assets. Privacy policy. | 1 wk |
| **7. Launch** | Soft launch in one country, watch metrics, fix issues, gradual rollout. | 1 wk |

**Total: ~7 focused weeks for one developer.**

---

## 13. Open Questions

1. **Hosting:** Hetzner / Fly.io / Railway? (Recommend Hetzner Germany or Finland — best price/perf, low MENA latency.)
2. **Launch markets:** global day 1, or one country first?
3. **Monetization:** if free forever, design data minimization more aggressively from day 1.
4. **Brand & name:** decide before code (changes app bundle IDs, hard to change later).
5. **Scholarly review:** who reviews the spiritual design choices in §9?
6. **Push notifications:** daily reminder? FCM is free.
7. **Streaks:** strong retention driver, but again — *riya'* risk. Discuss.

---

## 14. Repo Layout (proposed)

```
salawat-app/
├── docs/
│   └── ARCHITECTURE.md          (this file)
├── mobile/                      Flutter app
│   ├── lib/
│   ├── test/
│   └── pubspec.yaml
├── backend/                     Node + Fastify
│   ├── src/
│   │   ├── routes/
│   │   ├── services/
│   │   ├── db/
│   │   └── server.ts
│   ├── migrations/              Postgres schema
│   ├── package.json
│   └── tsconfig.json
├── infra/
│   ├── docker-compose.yml       single-host MVP
│   ├── Caddyfile
│   └── prometheus/
└── README.md
```
