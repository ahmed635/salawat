# صلوا عليه — Salawat Counter

A Flutter Android app for counting Salawat (prayers upon the Prophet ﷺ),
with a global community counter and leaderboard. Backed by Firebase.

## Repo layout

```
salawat-app/
├── mobile/             Flutter Android app (Riverpod, Material 3)
├── functions/          Cloud Functions (TypeScript) — incrementCount callable
├── reference/          Original React + Firebase prototype (preserved)
├── docs/               ARCHITECTURE, FLUTTER-CONVERSION, SETUP, EMULATORS
├── firebase.json       Firestore rules / indexes / functions / emulators config
├── firestore.rules     Locked-down rules — counter writes go through the function
├── firestore.indexes.json
└── .firebaserc         Default project: salawat-e1098
```

## Quick start (after cloning)

You need: **Flutter 3.27+**, **Node 22**, **Firebase CLI 14+**, **Java 17+**.

```bash
# 1. Re-generate the gitignored Firebase config (needs the project's Google account)
cd mobile
flutterfire configure --project=salawat-e1098 --platforms=android --yes

# 2. Install deps
flutter pub get
cd ../functions && npm install && cd ..

# 3. Run the app
cd mobile
flutter run
```

## Detailed docs

- **`docs/FLUTTER-CONVERSION.md`** — full architecture + 9-phase plan
- **`docs/SETUP.md`** — first-time Firebase setup (Auth, Firestore, Blaze, deploy)
- **`docs/EMULATORS.md`** — local development with Firebase Emulator Suite
- **`docs/ARCHITECTURE.md`** — original Node + Postgres design (superseded; kept for reference)
