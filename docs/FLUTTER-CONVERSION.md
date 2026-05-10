# Flutter Conversion Plan — صلوا عليه (Sallou)

Source: an existing **React 18 + Firebase Web SDK** prototype (preserved at [`../reference/sallou-app.jsx`](../reference/sallou-app.jsx)).
Target: a **Flutter** mobile app (iOS + Android) backed by Firebase.

---

## 1. Source App Inventory

**Name:** صلوا عليه (Sallou Alayh)
**Direction:** RTL Arabic, Cairo font
**Tech:** React 18, Tailwind CSS, `lucide-react`, Firebase Web SDK 10+ (Firestore + Anonymous Auth)

### Screens
1. **Onboarding** — name input, persisted to localStorage
2. **Home** — global progress bar (target 1M/day), big tap button with ripples + counter + "صَلِّ عَلَيْهِ" label, next-badge progress card
3. **Leaderboard** — top 50 list, current user row highlighted, sticky-bottom card if user's rank > 50
4. **Profile** — gradient header with name + total, 8-badge grid showing unlock progress

### Features
- Tap counter with sine-wave audio (Web Audio API) + 20ms haptic
- Achievement unlock with chord audio + `[100,50,100]` haptic + toast
- 8 badges (10 → 100,000)
- Daily global goal (1,000,000)
- Light/dark theme toggle, persisted
- Native share (`navigator.share`)
- Real-time global counter + leaderboard via Firestore listeners
- Batched writes every 2.5s + flush on tab close / unmount

### Firestore schema (current)
```
artifacts/{appId}/public/data/stats/global       { totalCount }
artifacts/{appId}/public/data/leaderboard/{uid}  { name, count, updatedAt }
```

---

## 2. Scaling Gaps in Source Code (must fix during port)

You said **"millions of users"** earlier. The source has 4 issues that block that. Don't port these as-is.

| # | Problem | Impact at 100K+ users | Fix |
|---|---|---|---|
| 1 | Listens to **entire** `leaderboard` collection (`onSnapshot(collection(...))`) and sorts client-side | Each client downloads the full collection. At 100K users that's MBs per device, and every change refans to every listener. Bandwidth + Firestore read cost explodes. | Server-side: `query(collection, orderBy('count','desc'), limit(50))`. Show user's own rank via separate query. |
| 2 | Single global counter doc with `increment()` | Firestore caps writes to ~1/sec/document. At peak you'll throttle and lose increments. | **Distributed counter** — N shards (typically 10), client writes to a random shard, read = sum. Canonical Firebase pattern. |
| 3 | No daily reset (UI says "صلاة اليوم" / today's prayers, but stored count is lifetime) | Leaderboard becomes static — early adopters unbeatable, engagement dies after week 1 | Add `leaderboard_daily/{YYYY-MM-DD}/users/{uid}`. Show daily on home, lifetime on profile. |
| 4 | No server-side validation. Client writes counts directly. | Anyone opens devtools → writes arbitrary counts. Leaderboard meaningless. | Cloud **Function** for `incrementCount` (callable, validated, rate-limited, idempotent). Lock Firestore rules so client cannot write counter docs directly. |

**Recommendation:** port the UX as a 1:1 visual clone, but with a **rewritten data layer** (Cloud Function for writes + sharded counter + capped leaderboard query). Same look, scalable infrastructure.

---

## 3. Tech Stack Mapping

| React / Web | Flutter |
|---|---|
| React 18 + hooks | Flutter 3.x + **Riverpod 2** |
| Tailwind CSS | Custom `ThemeData` + small reusable widgets |
| `lucide-react` | `lucide_icons_flutter` package (or Material icons where they match) |
| `localStorage` | `shared_preferences` |
| Firebase Web SDK | `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions`, `firebase_messaging` (FlutterFire) |
| `navigator.vibrate(20)` | `HapticFeedback.lightImpact()` (built-in) |
| `navigator.vibrate([100,50,100])` | `vibration` package (custom patterns) |
| Web Audio API (oscillator) | Pre-recorded `.wav` via `audioplayers` (smaller, more reliable, cross-platform) |
| `navigator.share` | `share_plus` |
| Cairo Google Font | `google_fonts` package |
| `dir="rtl"` | Wrap app in `Directionality(textDirection: TextDirection.rtl)` |
| Tailwind dark mode | `ThemeMode.system` + `lightTheme`/`darkTheme` `ThemeData` |
| Custom bottom nav | `NavigationBar` (Material 3) |
| `onSnapshot` listeners | Riverpod `StreamProvider` wrapping Firestore `.snapshots()` |
| Toast notifications | Custom `OverlayEntry` (matches source visual) or `fluttertoast` |
| Tailwind keyframes (`fade-in-down`, `ripple`) | `AnimatedScale`, `AnimatedOpacity`, custom `AnimationController` for ripple |
| `toLocaleString('ar-EG')` | `intl` package: `NumberFormat.decimalPattern('ar')` |
| Tailwind gradients | `LinearGradient` in `BoxDecoration` |

---

## 4. Flutter Project Structure

```
salawat-app/
├── docs/
│   ├── ARCHITECTURE.md         (Node version — superseded, kept for reference)
│   └── FLUTTER-CONVERSION.md   (this file)
├── reference/
│   └── sallou-app.jsx          (original React source)
├── mobile/                      Flutter project
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── theme/
│   │   │   ├── app_theme.dart
│   │   │   └── colors.dart
│   │   ├── core/
│   │   │   ├── firebase_options.dart   (generated by `flutterfire configure`)
│   │   │   ├── haptics.dart
│   │   │   ├── audio.dart
│   │   │   ├── prefs.dart
│   │   │   └── arabic_numbers.dart
│   │   ├── data/
│   │   │   ├── firestore_paths.dart
│   │   │   ├── auth_repository.dart
│   │   │   ├── counter_repository.dart       (calls Cloud Function)
│   │   │   └── leaderboard_repository.dart   (top-N + my-rank queries)
│   │   ├── models/
│   │   │   ├── badge.dart
│   │   │   └── leaderboard_entry.dart
│   │   ├── features/
│   │   │   ├── onboarding/
│   │   │   │   └── onboarding_screen.dart
│   │   │   ├── home/
│   │   │   │   ├── home_screen.dart
│   │   │   │   ├── tap_button.dart           (ripple + counter)
│   │   │   │   ├── global_goal_card.dart
│   │   │   │   └── next_badge_card.dart
│   │   │   ├── leaderboard/
│   │   │   │   ├── leaderboard_screen.dart
│   │   │   │   └── rank_row.dart
│   │   │   └── profile/
│   │   │       ├── profile_screen.dart
│   │   │       └── badge_card.dart
│   │   └── shared/
│   │       ├── nav_shell.dart                (bottom nav + header)
│   │       └── toast.dart
│   ├── assets/
│   │   ├── audio/{tap.wav, achievement.wav}
│   │   └── images/
│   ├── android/  ios/
│   ├── pubspec.yaml
│   └── analysis_options.yaml
├── functions/                   Cloud Functions (TypeScript)
│   ├── src/
│   │   ├── index.ts
│   │   ├── incrementCount.ts    (callable: validate + sharded write)
│   │   ├── dailyReset.ts        (scheduled: rotate daily leaderboard pointer)
│   │   └── cleanupIdempotency.ts (scheduled: drop expired idem docs)
│   ├── package.json
│   └── tsconfig.json
└── firebase.json
└── firestore.rules
└── firestore.indexes.json
```

---

## 5. Firestore Data Model (rewritten for scale)

```
sallou/                          (use a real top-level path, drop the artifacts/{appId} wrapper)
├── stats/
│   ├── global_shards/{0..9}     { count: int }   ← sharded counter
│   ├── meta                     { dailyGoal, lastDailyReset }
│   └── community_daily/{YYYY-MM-DD}  { count }
├── leaderboard_lifetime/{uid}   { name, count, country, updatedAt }
├── leaderboard_daily/
│   └── {YYYY-MM-DD}/users/{uid} { name, count }
├── users/{uid}                  { displayName, country, createdAt, totalCount, badgesUnlocked: [int] }
└── idempotency/{clientReqId}    { uid, processedAt, expiresAt }   (TTL via scheduled cleanup)
```

**Key changes vs source:**
- Global counter is **10 sharded docs** instead of 1 (canonical Firestore pattern). Client writes random shard. Read = sum.
- Leaderboard query is `orderBy('count', desc).limit(50)` — never the whole collection.
- Daily leaderboard partitioned by date — daily reset = "stop reading old date, start reading new" (no batch delete needed).
- Profile separate from leaderboard entry — leaderboard doc has only `name + count` (privacy: don't leak email, country, etc. to all clients).

---

## 6. Counter Write Path

```
Flutter tap
  → in-memory + shared_prefs (instant — no spinner)
  → batch every 2.5s (matches source) OR on app background

Batched flush (Cloud Function callable):
  incrementCount({ delta, clientReqId })
    1. verify auth (Firebase auto)
    2. verify delta >= 1 && delta <= 100  (else 400 — split larger batches)
    3. rate limit: max 1 call per 2s per uid (Firestore tx on user doc OR Memorystore)
    4. idempotency: tx on idempotency/{clientReqId} → if exists, return cached
    5. transactional batch:
       - increment global_shards/{rand 0-9}.count by delta
       - increment leaderboard_lifetime/{uid}.count by delta
       - increment leaderboard_daily/{today}/users/{uid}.count by delta
       - increment users/{uid}.totalCount by delta
       - create idempotency/{clientReqId} (expires in 24h)
    6. return { newTotal }
```

**Firestore rules:** clients **cannot write** any counter doc directly. All writes through the function.

```js
// firestore.rules (sketch)
match /databases/{db}/documents {
  match /stats/{document=**}        { allow read; allow write: if false; }
  match /leaderboard_lifetime/{doc} { allow read; allow write: if false; }
  match /leaderboard_daily/{date}/users/{doc} { allow read; allow write: if false; }
  match /users/{uid} {
    allow read: if request.auth.uid == uid;
    allow update: if request.auth.uid == uid
                 && request.resource.data.diff(resource.data).changedKeys().hasOnly(['displayName', 'country']);
    allow create: if request.auth.uid == uid;
  }
  match /idempotency/{any}          { allow read, write: if false; }
}
```

---

## 7. Auth

- App start → `signInAnonymously()` (FlutterFire) → cached Firebase user, persisted across launches
- Onboarding screen captures `displayName` → write to `users/{uid}` (allowed) and `leaderboard_lifetime/{uid}` is created lazily by the first `incrementCount` call
- (Phase 8, optional) "Sign in with Google/Apple" → `linkWithCredential` upgrades the anon user, preserves count

---

## 8. Phased Plan

| Phase | Scope | Est. |
|---|---|---|
| **1. Bootstrap** | Flutter project + `flutterfire configure`, theme (light + dark), RTL, Cairo via `google_fonts`, navigation shell with 3 empty tabs | 2 days |
| **2. Onboarding + Home (offline-only)** | Name input → `shared_preferences`. Home tap button + ripple + local counter + badge progress. No Firebase yet. | 2 days |
| **3. Firebase + Cloud Function** | Anon auth, `incrementCount` callable, sharded global counter, lifetime + daily writes, Firestore rules locked. End-to-end one tap → server. | 3 days |
| **4. Leaderboard tab** | Stream top 50 (Firestore query), separate query for "my rank", sticky bottom card if rank > 50 | 2 days |
| **5. Profile tab** | Badge grid with unlock states, gradient header, badge unlock celebration | 1 day |
| **6. Polish** | Audio (record `.wav` once, ship in assets), haptics, toast notifications, share, dark mode toggle, ripple animation | 3 days |
| **7. Daily reset + retention** | Scheduled function for daily reset, FCM setup + daily reminder push | 2 days |
| **8. Anti-cheat hardening** | Rate-limit edge cases, anomaly detection job (nightly), audit log | 2 days |
| **9. Store prep** | Icons, splash, screenshots AR/EN, privacy policy, store listings | 2 days |

**~3 weeks** for one developer at full focus.

---

## 9. Open Questions (please answer before Phase 1)

1. **Firebase project** — create new, or do you have one already? (Need project ID for `flutterfire configure`.)
2. **App name in stores** — the React app shows `sallou-app-v2` and "صلوا عليه" — confirm name + bundle IDs (`com.example.sallou` or similar). Hard to change after launch.
3. **iOS, Android, or both?** Android first is faster (no Apple Dev account = $99/yr blocker).
4. **Daily reset:** make today's count the leaderboard scoring metric, or keep lifetime? (Today is healthier for engagement and matches the "صلاة اليوم" UI.)
5. **Drop the Web Audio synth** for pre-recorded WAVs? (Recommend yes — 2 KB shipped audio is more reliable than runtime synthesis on mobile.)
6. **Push notifications:** daily reminder ("you haven't said Salawat today")? FCM is free.
7. **Anti-cheat:** strict from day 1, or soft launch with monitoring first?
8. **Adopt the §9 spiritual considerations** from the original ARCHITECTURE.md (tier display, opt-in leaderboard, anonymous names by default)? The current React app is pure rank-based — worth a discussion before launch.

---

Ready to start **Phase 1** once questions 1–3 are answered.
