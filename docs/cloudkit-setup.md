# iCloud / CloudKit team sync

Gardens shares inventory with **Apple CloudKit** — not Google, not Firebase.

- Login = the **iCloud / Apple ID** already on the iPhone (Settings → [your name]).
- Each plant type, physical plant, and care event is its **own CloudKit record**.
- Photos are **CKAssets** on plant instance records.
- Data lives in the container `iCloud.com.gardens.intake` **public database** so every teammate with the app + iCloud sees the same inventory.

Until iCloud is available, the app uses on-device SwiftData for that phone only.

## 1. Apple Developer

1. Certificates, Identifiers & Profiles → Identifiers → App ID `com.gardens.intake`.
2. Enable **iCloud** → **CloudKit**.
3. Create / select container **`iCloud.com.gardens.intake`** (must match `CloudKitPlantRepository.containerID` and `Gardens.entitlements`).

## 2. Xcode

1. Open `Gardens/Gardens.xcodeproj`.
2. Signing Team set; entitlements file is `Gardens/Resources/Gardens.entitlements`.
3. Run on a real iPhone signed into iCloud (Simulator iCloud can be flaky).

## 3. CloudKit Dashboard (first run)

1. [CloudKit Console](https://icloud.developer.apple.com/) → your container → **Public Database**.
2. After the first successful save from the app, confirm record types exist (or create them):

| Record type | Key fields |
| --- | --- |
| `CatalogItem` | `id`, `name`, `genus`, `careInstructions`, `wateringCheckGuidance`, `healthCheckGuidance`, `createdAt` |
| `PlantInstance` | `id`, `catalogItemID`, `arrivedOn`, `vendor`, `photo` (Asset), `createdAt` |
| `CareEvent` | `id`, `instanceID`, `kind`, `performedAt`, `wateringObservation`, `healthObservation`, `notes` |

3. Deploy Development → Production when you’re ready for TestFlight / App Store.

## 4. Test a record (smoke test)

1. Run Gardens from Xcode on an iPhone signed into iCloud.
2. Tap **Sync** → **Connect iCloud** (status should say iCloud connected).
3. Tap **Write test plant + care note**.
4. Expect **Test OK** and a list row named **Gardens Sync Test**.
5. In [CloudKit Console](https://icloud.developer.apple.com/) → container `iCloud.com.gardens.intake` → **Public Database** → Records, confirm `CatalogItem` / `PlantInstance` / `CareEvent`.

If the write fails with “not authenticated” / account errors, fix iCloud sign-in and the App ID CloudKit container first.

## 5. Team use

1. Each person: iPhone → Settings → signed into **iCloud** with their Apple ID.
2. Open Gardens → **Sync** → **Connect iCloud**.
3. Adds and care logs appear on other signed-in iPhones (list refreshes about every 20s; pull to refresh anytime).

## Notes

- No `GoogleService-Info.plist`, no Firebase, no Google Sign-In.
- GitHub repo private/public does not affect CloudKit sync.
- Public CloudKit DB is appropriate for an internal staff app; tighten later with private DB + CKShare if you need invite-only sharing.
