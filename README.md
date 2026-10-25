# Gardens

iOS plant intake app (SwiftUI) with a shared `GardensCore` package. Inventory can stay on-device (SwiftData) or sync **record-by-record** across your Google Workspace team via **Cloud Firestore**.

## Open & run

1. On a Mac, open `Gardens/Gardens.xcodeproj` in Xcode 15+.
2. Select an iOS 17+ Simulator or device.
3. Set your Development Team under Signing.
4. Run (⌘R).

### Team sync (Firestore)

Follow **[docs/firestore-setup.md](docs/firestore-setup.md)** — create a Firebase project, add `GoogleService-Info.plist`, enable Google Auth + Firestore + Storage, then use **Sync** in the app to sign in with Workspace Google accounts.

## What’s included

- **Catalog vs instance** — plant types reused by name+genus; each physical plant is its own instance.
- **Intake** — new or existing type; quantity creates N unique instances + batch QR print.
- **Scan + care log** — QR lookup, maintenance / watering / health observations.
- **Team sync** — Firestore documents + Storage photos; live updates when signed in.
- **Local fallback** — SwiftData if Firebase isn’t configured yet.
- **Compact QR** — `gardens://plant/<uuid>` deep links.

## Layout

```
GardensCore/          Shared models + QR + PlantRepository protocol
Gardens/              iOS app (SwiftUI, SwiftData, Firestore, camera, print)
firebase/             Suggested Firestore + Storage security rules
docs/                 Architecture + Firestore setup
```

No store-location field (intentionally omitted).
