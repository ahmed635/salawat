# Setup — what you need to do yourself

These steps need your Google account or a real device, so I can't do them for you.

---

## Phase 1 + 2 (already done by you)

```powershell
firebase login
flutterfire configure --project=salawat-9f855 --platforms=android --yes
```

`lib/firebase_options.dart` and `android/app/google-services.json` are in place.

---

## Phase 3 — Backend setup

### 0. Enable Anonymous Authentication (one-time, easy to forget)

> **You'll get `auth/unknown. configuration not found` on app start if you skip this.**
>
> 1. Open https://console.firebase.google.com/project/salawat-9f855/authentication/providers
> 2. If prompted, click **Get Started** first.
> 3. Click **Anonymous** → toggle **Enable** → **Save**.

### A. Upgrade your Firebase project to Blaze (pay-as-you-go)

> **Required for Cloud Functions.** Cloud Functions (and the Cloud Build that
> compiles them) cannot be deployed on the free Spark plan.
>
> - Go to: https://console.firebase.google.com/project/salawat-9f855/usage/details
> - Click "Modify plan" → choose **Blaze**.
> - Set a **budget alert** at e.g. $5/month so a misbehaving loop can't surprise
>   you. Open: https://console.cloud.google.com/billing/budgets
>
> Realistic cost at this stage: **~$0/month** until you have thousands of DAU.
> The free tier on Blaze gives you 2M function invocations + 50K Firestore
> reads/day at no charge.

### B. Install Cloud Functions deps + first deploy

```powershell
cd C:\salawat-app\functions
npm install
cd ..
firebase deploy --only firestore:rules,firestore:indexes,functions
```

What this does:
- Locks down Firestore — clients cannot write counter docs directly any more.
- Deploys the `incrementCount` callable Cloud Function to `us-central1`.

The first deploy takes 3–5 minutes (Cloud Build provisions the runtime).

### C. Verify the function is live

```powershell
firebase functions:list
# Expect: incrementCount (callable, us-central1, node22)

firebase functions:log --only incrementCount
# Tail logs while you tap in the app.
```

---

## Running the Flutter app

```powershell
cd C:\salawat-app\mobile
flutter run
```

The first launch should:
1. Sign you in anonymously (silent — no UI).
2. Show the onboarding card → enter your name.
3. Land on the home shell.
4. Tap the big button — count goes up locally instantly.
5. Within ~2.5s, `incrementCount` fires and the global counter starts climbing
   (you'll see the same change reflected on a second device using the same
   Firestore project).

If the function isn't deployed yet, the local counter still works (taps queue
locally and flush when the function comes online — that's the whole point of
the batched-delta design).

---

## Files written in Phase 3

```
C:\salawat-app\
├── firebase.json                     project config
├── firestore.rules                   client write lock
├── firestore.indexes.json            count DESC index for leaderboard (Phase 4)
├── functions/
│   ├── package.json                  firebase-functions v6, firebase-admin v12
│   ├── tsconfig.json
│   ├── .gitignore
│   └── src/
│       ├── index.ts                  exports
│       └── incrementCount.ts         callable: validate + sharded write
└── mobile/lib/
    ├── main.dart                     Firebase.initializeApp
    ├── app.dart                      AuthGate + lifecycle observer for sync-on-pause
    ├── core/prefs.dart               + lastSyncedCount + pendingReqId
    ├── data/
    │   ├── firestore_paths.dart      single source of truth for paths
    │   ├── auth_repository.dart      anonymous sign-in
    │   ├── user_repository.dart      profile upsert in users/{uid}
    │   ├── global_count_repository.dart   stream sum of 10 shards
    │   └── counter_sync.dart         batched flush every 2.5s + on app pause
    └── features/home/home_screen.dart  now reads live global count
```

## What I could not verify without your device + deploy

- End-to-end: tap → function call → Firestore write → second client sees update.
- The sync timer's behaviour around app lifecycle on real Android (paused,
  killed, resumed). Logic is correct; OS-level edge cases need a device.
- Cloud Function cold-start time on first invocation (typically 1–3 seconds
  on Node 22).
