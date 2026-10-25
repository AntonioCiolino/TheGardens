# Firestore team sync setup

Gardens stores shared inventory in **Cloud Firestore** (one document per plant / care event) with photos in **Firebase Storage**.

**Login is Sign in with Apple** — teammates need an **Apple ID / iCloud account**. There is no Google login in the app. (Firebase still hosts the database; it is not used as the identity provider the staff taps.)

Until Firebase is configured, the app runs on **on-device SwiftData** (that phone only).

## 1. Create a Firebase project

1. Open [Firebase Console](https://console.firebase.google.com/).
2. Add a project (e.g. `the-gardens`).
3. Add an **iOS app** with bundle ID `com.gardens.intake`.
4. Download `GoogleService-Info.plist` (Firebase’s config filename — still required even though users sign in with Apple).

## 2. Drop the plist into Xcode

1. Copy to `Gardens/Gardens/Resources/GoogleService-Info.plist`.
2. Confirm it’s in the Gardens target (Copy Bundle Resources).
3. Signing: the target already has `Gardens.entitlements` with **Sign in with Apple**.

## 3. Enable Sign in with Apple (Firebase + Apple)

### Apple Developer

1. Certificates, Identifiers & Profiles → Identifiers → App ID `com.gardens.intake`.
2. Enable **Sign in with Apple**.
3. (Optional) Services ID if you later add web; not required for iPhone-only.

### Firebase

1. **Authentication** → Sign-in method → enable **Apple** (not Google).
2. Follow Firebase’s Apple provider steps (Services ID / key as prompted for your account type).

### Data products

1. **Firestore** → create database → deploy `firebase/firestore.rules`.
2. **Storage** → enable → deploy `firebase/storage.rules`.

Rules only require a signed-in Firebase user (which will be an Apple ID session):

```
allow read, write: if request.auth != null;
```

## 4. Xcode packages

- `firebase-ios-sdk` → FirebaseAuth, FirebaseFirestore, FirebaseStorage  
- Sign in with Apple uses Apple’s **AuthenticationServices** (system framework) — no Google Sign-In package.

## 5. Use it

1. Launch Gardens on an **iPhone** → **Sync**.
2. **Sign in with Apple** (Apple ID / iCloud).
3. Other team iPhones do the same; inventory and care history sync live.

## Data layout

```
workspaces/default/catalog/{uuid}
workspaces/default/instances/{uuid}
workspaces/default/careEvents/{uuid}
workspaces/default/photos/{uuid}.jpg    (Storage)
```

QR codes still encode the instance UUID. Any signed-in teammate can open that plant from the shared store.
