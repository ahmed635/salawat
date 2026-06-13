# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter mobile app (`name: app`, package `app`) for **صلوا عليه (Sallou)** — a salawat (sending peace upon the Prophet ﷺ) tap-counter with a global community goal, leaderboards, and badges. Arabic-first (RTL, Cairo font, Arabic-Indic digits via `intl`).

This is one piece of a larger project (`C:\salawat-app\`) that also contains a Cloud Functions backend (`functions/`), Firestore rules/indexes, and design docs (`docs/`). The mobile app talks to that backend — when changing the wire format (Cloud Function inputs/outputs, Firestore document shapes), update both sides.

The app was ported from a React prototype at `../reference/sallou-app.jsx`. The visual design is intentionally a 1:1 clone, but the data layer was rewritten for scale — see `../docs/FLUTTER-CONVERSION.md` §2. **Do not "port" patterns back from the reference if they conflict with the current data layer.**

## Commands

Run from the `mobile/` directory:

- `flutter pub get` — fetch dependencies
- `flutter run` — debug build on a connected device/emulator
- `flutter analyze` — static analysis (lints from `flutter_lints`); `tools/**` is excluded
- `flutter test` — full test suite (`test/widget_test.dart` covers badges, formatting, leaderboard model, onboarding/profile widgets)
- `flutter test test/widget_test.dart -p chrome` — single file
- `flutter test --plain-name "badgeUnlockedAt"` — single test by name
- `dart run tools/generate_audio.dart` — regenerate `assets/audio/{tap,achievement}.wav` from synthesis params (re-run any time the params in that file change)
- `flutter build apk` / `flutter build appbundle` — Android release artifacts

Firebase: project ID `salawat-e1098`. Config is committed (`firebase.json`, `lib/firebase_options.dart`). If you add a platform or rename the app, regenerate via `flutterfire configure`.

## Architecture

### State management — Riverpod 2

All shared state goes through Riverpod providers. Do **not** introduce another state-management library or use `setState` for state that crosses widget boundaries.

- `prefsProvider` — overridden in `main()` after `Prefs.load()`. Throws if used without override. Every controller that touches persistent state reads through this.
- Controllers (`Notifier`s) live in `lib/core/`: `CounterController`, `ThemeController`, `UserNameController`. They mutate `Prefs` and update local state synchronously, then persist asynchronously.
- Repositories live in `lib/data/` and own all Firebase calls. UI never touches `FirebaseFirestore` / `FirebaseAuth` / `FirebaseFunctions` directly — go through a repository.
- All Firestore paths are centralized in `lib/data/firestore_paths.dart`. **Add new paths there**, don't inline them.

### The counter sync — non-obvious design

This is the core piece, and it's easy to break by "simplifying" it. See `lib/data/counter_sync.dart` and `lib/core/counter_controller.dart`.

- A tap increments `localCount` in `Prefs` immediately. UI reads from `counterControllerProvider` — **never block a tap on the network.**
- `CounterSync` runs a 2.5s timer. Each tick, if `localCount > lastSyncedCount`, it calls the `incrementCount` Cloud Function with the delta and a persisted UUID (`pendingReqId`). The server dedupes via that UUID, so retries-after-kill are safe.
- `lastSyncedCount` is captured **before** the call, so taps that happen during the in-flight call go in the next batch (not lost).
- `_AuthGate.didChangeAppLifecycleState` calls `flushNow()` on pause/inactive — best-effort flush before backgrounding.
- The sync timer is started in `_AuthGate` only **after** `ensureSignedInProvider` resolves. Anonymous sign-in must complete first.

If you change batching, deltas, or idempotency, update `../functions/src/incrementCount.ts` to match (`MAX_DELTA_PER_CALL`, request shape, idempotency-key length validation).

### Leaderboard rank — throttled aggregation

`LeaderboardRepository.watchMyRank` (`lib/data/leaderboard_repository.dart`) uses a Firestore `count()` aggregation to find the user's rank. It's intentionally throttled (`_rankRecomputeWindow = 30s`, plus a "count moved by >5" gate) so a burst of taps doesn't fan out into many aggregation queries. Don't remove the throttle — at scale this becomes a real cost. The doc comment notes the >500K-user point at which we'd switch to a tier display.

### Global counter — sharded

Reading: `GlobalCountRepository.watch()` streams all 10 docs in `globalShards/` and sums them. The collection is small enough that a `.snapshots()` listener is fine. Writing: never from the client — the server's `incrementCount` writes a random shard. Firestore rules deny client writes to `globalShards/*`.

### Auth

Anonymous Firebase Auth, kicked off by `ensureSignedInProvider` at app start. The user gets a UID on first launch and keeps it across sessions (FirebaseAuth persists). Display name is collected separately via `OnboardingScreen` — `userName == null` in `Prefs` is the gate between onboarding and the main shell.

### Theme & locale

- Theme: `AppTheme.light()/dark()` in `lib/theme/app_theme.dart`, seeded from `AppColors.emerald600`. Toggle via `ThemeController`. Colors live in `lib/theme/colors.dart` — use these constants instead of hardcoding.
- Locale: hardcoded `Locale('ar')`. RTL is implicit from the locale. Numbers should be formatted via `core/arabic_numbers.dart` (`formatArabic`) so digits render Arabic-Indic.

### Audio & haptics

- `Audio.instance.init()` is called once in `main()` to pre-decode WAVs and avoid first-tap latency. Two `AudioPlayer`s (one per sound) so a tap can play while the achievement chime is still ringing.
- WAV files are generated, not hand-authored — edit synth params in `tools/generate_audio.dart` and re-run the tool. Do **not** check in WAVs edited by other means.
- Haptics in `core/haptics.dart`. Tap = 20ms light, achievement = `[100,50,100]` pattern (mirrors the React source).

### Badges

`lib/models/badge.dart` defines the 11-rung ladder. `badgeUnlockedAt(before, after)` returns the highest badge whose `requirement` falls in `(before, after]` — i.e. the rung **crossed** by a tap (used to fire celebration UX), which is robust to non-incremental jumps like the lifetime-count migration. `nextBadgeFor` and `previousBadgeRequirement` drive progress UI. The list is required to be sorted ascending by `requirement` — a test enforces this.

### Feature folders

`lib/features/{onboarding,home,leaderboard,profile}/` each contain a screen + a `widgets/` subfolder for screen-local widgets. The bottom nav and shared header live in `lib/shared/nav_shell.dart`. The shell uses `IndexedStack` so screen state is preserved when switching tabs.

## Conventions

- The package name is `app` (from `pubspec.yaml`). Internal imports use `package:app/...` (visible in `test/widget_test.dart`).
- New repository / controller / provider? Match the existing file layout (`data/` vs `core/` vs `features/`) — don't introduce new top-level folders without reason.
- Comments in this codebase explain *why*, not *what*. Match that style. Many files have a short doc comment at the top describing the design intent — preserve and update it when behavior changes.
- Tests are colocated in `test/` rather than per-feature. The existing file mixes unit and widget tests; keep adding to it unless it grows unwieldy.
