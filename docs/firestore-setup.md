# Firestore team sync setup

Gardens can store inventory in **Cloud Firestore** (record per plant / care event) with photos in **Firebase Storage**, and sign people in with **Google** (Workspace accounts work).

Until Firebase is configured, the app still runs on **on-device SwiftData** (single phone only).

## 1. Create a Firebase project

1. Open [Firebase Console](https://console.firebase.google.com/) with your Workspace admin Google account.
2. Add a project (e.g. `the-gardens`).
3. Add an **iOS app** with bundle ID `com.gardens.intake`.
4. Download `GoogleService-Info.plist`.

## 2. Drop the plist into Xcode

1. Copy the downloaded file to:
   `Gardens/Gardens/Resources/GoogleService-Info.plist`
2. Confirm it’s in the Gardens app target (Copy Bundle Resources).
3. From that plist, copy `REVERSED_CLIENT_ID` and add it as a URL scheme in `Info.plist` under `CFBundleURLTypes` (alongside `gardens`).

Example URL type entry:

```xml
<dict>
  <key>CFBundleTypeRole</key>
  <string>Editor</string>
  <key>CFBundleURLSchemes</key>
  <array>
    <string>com.googleusercontent.apps.YOUR_REVERSED_ID_SUFFIX</string>
  </array>
</dict>
```

## 3. Enable products

In Firebase Console:

1. **Authentication** → Sign-in method → enable **Google**.
2. **Firestore Database** → create database (start in production mode) → deploy rules from `firebase/firestore.rules`.
3. **Storage** → enable → deploy rules from `firebase/storage.rules`.

Optional: restrict rules to your Workspace domain:

```
allow read, write: if request.auth != null
  && request.auth.token.email.matches('.*@yourcompany[.]com$');
```

## 4. Xcode packages

The Gardens project already references:

- `firebase-ios-sdk` → FirebaseAuth, FirebaseFirestore, FirebaseStorage  
- `GoogleSignIn-iOS` → GoogleSignIn  

Open `Gardens/Gardens.xcodeproj`, let packages resolve, set your Team, run.

## 5. Use it

1. Launch Gardens → **Sync** (cloud icon).
2. **Continue with Google** using each teammate’s Workspace account.
3. Adds, care logs, and photos appear on every signed-in device (live listeners).

## Data layout

```
workspaces/default/catalog/{uuid}       plant types
workspaces/default/instances/{uuid}     physical plants (photoPath → Storage)
workspaces/default/careEvents/{uuid}    care / health history
workspaces/default/photos/{uuid}.jpg    Storage
```

QR codes still encode the **instance UUID**. Any signed-in device can open that plant because the record lives in Firestore, not only on the phone that created it.
