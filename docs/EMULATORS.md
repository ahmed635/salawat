# Local development with Firebase Emulators

You don't need the Blaze plan to test the full backend locally. The Firebase
Emulator Suite runs Auth + Firestore + Cloud Functions on your machine for
free. The Flutter app is already wired to use them in debug mode.

---

## One-time setup

### 1. Install Java (if you don't already have it)

The Firestore emulator needs **Java 11+**. Verify:

```powershell
java -version
```

If missing, install Microsoft's free build:
https://learn.microsoft.com/en-us/java/openjdk/download

### 2. Install function dependencies + build

```powershell
cd C:\salawat-app\functions
npm install
npm run build
```

The build step compiles TypeScript to `lib/` (the emulator runs the JS).

---

## Daily workflow

### Two terminals

**Terminal A — emulators** (leave running)

```powershell
cd C:\salawat-app
firebase emulators:start --only auth,firestore,functions
```

You'll see something like:

```
┌─────────────────────────────────────────────────────────────┐
│ ✔  All emulators ready! View status and logs at http://localhost:4000 │
├──────────────┬────────────────┬──────────────────────────────┤
│ Emulator     │ Host:Port      │ View in Emulator UI          │
├──────────────┼────────────────┼──────────────────────────────┤
│ Authentication│ localhost:9099│ http://localhost:4000/auth   │
│ Functions    │ localhost:5001 │ http://localhost:4000/...    │
│ Firestore    │ localhost:8080 │ http://localhost:4000/...    │
└──────────────┴────────────────┴──────────────────────────────┘
```

Open **http://localhost:4000** in your browser — the Emulator UI lets you:
- Inspect Firestore data live as the app writes
- See function invocation logs
- Inspect anonymous users
- Wipe state between tests

**Terminal B — Flutter app**

```powershell
cd C:\salawat-app\mobile
flutter run
```

The app's debug console will print:

```
Using Firebase emulators @ 10.0.2.2
```

…confirming it's hitting the emulators, not production Firebase.

### What changes vs production

- `10.0.2.2` is the Android emulator's loopback to your host machine. Already
  hardcoded in `lib/main.dart`.
- **Physical Android device on the same WiFi**: change `10.0.2.2` to your
  host's LAN IP (e.g. `192.168.1.42`) in `lib/main.dart`. Or run the app on
  the Android emulator.
- Function logs appear in Terminal A under "Functions" — much faster feedback
  than `firebase functions:log` against production.
- Firestore data is **in-memory** by default — wiped when emulators stop. Use
  `--export-on-exit ./.emulator-data` and `--import ./.emulator-data` to
  persist between sessions.

### Switching back to production Firebase

The emulator wiring is gated on `kDebugMode` (true for `flutter run`, false
for `flutter build apk --release`). To force a debug build to hit production:

```powershell
flutter run --dart-define=USE_EMULATORS=false
```

---

## End-to-end test you can run right now

1. Start emulators (Terminal A).
2. `flutter run` (Terminal B).
3. App signs in anonymously → onboarding card → enter your name.
4. Open the Emulator UI → Authentication → you should see one anonymous user.
5. Open Firestore → `users/{uid}` doc with your `displayName` is there.
6. Tap the big button 10+ times.
7. Within ~2.5s, watch Firestore:
   - `globalShards/{0..9}` — one of these incremented to 10
   - `leaderboardLifetime/{uid}` — `count: 10`, `name: "<your name>"`
   - `leaderboardDaily/2026-05-08/users/{uid}` — same
   - `idempotency/{uuid}` — record of the call
8. The home card's global counter (sum of shards) shows 10.
9. The leaderboard tab shows you at #1.

If any of the above doesn't happen, check Terminal A for function errors.

---

## When you're ready for real Firebase

Upgrade to Blaze and `firebase deploy --only firestore:rules,firestore:indexes,functions`.
Run a release build (`flutter build apk --release` then install) — automatically
talks to production with no code changes.
