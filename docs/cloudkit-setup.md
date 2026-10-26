# iCloud / CloudKit team sync

Gardens shares inventory with **Apple CloudKit**.

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

## 3. What the database actually stores

The public database only has the default zone (`AppDefaultZone`). Apple’s docs for `CKRecordZone.default()` say that zone cannot fetch record changes and cannot save a group of records atomically. The phone error `appdefaultzone does not support getChanges` is that limit — the previous build called `CKFetchRecordZoneChangesOperation`, and that call is gone.

This build only uses `CKDatabase.record(for:)` (read one record by ID) and `CKDatabase.save(_:)` (write one record). Those calls do not need a queryable index, so the dashboard does not need a `recordName` index.

One `InventoryManifest` record named `gardens-inventory` lists `catalogIDs` and `instanceIDs`. Care event IDs live on each `PlantInstance` (`careEventIDs`). A list field is omitted until it has at least one ID — CloudKit rejects an empty list as the first value of a new field (`cannot use an empty list to initialize a new field`). The app writes the plant record first, then adds its ID to the manifest. After a save it reads the record back by ID and fails the test if a required field is missing.

| Record type | Who creates it | Fields |
| --- | --- | --- |
| `InventoryManifest` | App, record name `gardens-inventory` | `catalogIDs` (String list), `instanceIDs` (String list) |
| `CatalogItem` | App, on first save of a plant type | `id`, `name`, `genus`, `careInstructions`, `wateringCheckGuidance`, `healthCheckGuidance`, `createdAt` |
| `PlantInstance` | App, one per physical plant | `id`, `catalogItemID`, `arrivedOn`, `vendor`, `photo` (Asset), `createdAt`, `careEventIDs` (String list) |
| `CareEvent` | App, one per care note | `id`, `instanceID`, `kind`, `performedAt`, `wateringObservation`, `healthObservation`, `notes` |
| `Users` | **Apple**, automatically | None. Leave it. Empty fields are expected. Do not add fields and do not delete this type. |

After **Write test plant**, confirm in [CloudKit Console](https://icloud.developer.apple.com/) → `iCloud.com.gardens.intake` → Development → Public Database → Records:

- one `InventoryManifest` named `gardens-inventory`
- one `CatalogItem` named Gardens Sync Test
- one `PlantInstance` with vendor Setup Check
- one `CareEvent`

The app reads the catalog, plant, and care records back by ID immediately after save and fails the test if a required field is missing. `Users` stays empty.

Deploy Development → Production when you ship TestFlight.

## 4. Test a record (smoke test)

1. Run Gardens from Xcode on an iPhone signed into iCloud.
2. Tap **Sync** → **Connect iCloud** (status should say iCloud connected).
3. Tap **Write test plant + care note**. This section is hidden when the list already has any plant — an existing record means the write path already succeeded.
4. Expect **Test OK** and a list row named **Gardens Sync Test**.
5. In [CloudKit Console](https://icloud.developer.apple.com/) → container `iCloud.com.gardens.intake` → **Public Database** → Records, confirm `CatalogItem` / `PlantInstance` / `CareEvent`.

If the write fails with “not authenticated” / account errors, fix iCloud sign-in and the App ID CloudKit container first.

## 5. Delete

Swipe a plant and confirm **Delete**. That calls `CKDatabase.deleteRecord` for the plant’s care notes, the `PlantInstance`, and — when no plant of that type remains — the `CatalogItem`. The app then reads each ID back. If the record is still there, Delete fails and the error stays on screen.

Existing type only lists types that still have a plant. A type with other plants still in the list stays, so you can add another of that plant.

CloudKit Console → Schema → Security Roles, Development:

- **World**: Read
- **Authenticated**: Create
- **Creator**: Read and Write

on `CatalogItem`, `PlantInstance`, `CareEvent`, and `InventoryManifest`. Creator without Write cannot delete, and the record stays in the public database. Deploy the schema to Production when you ship.

## 6. Team use

1. Each person: iPhone → Settings → signed into **iCloud** with their Apple ID.
2. Open Gardens → **Sync** → **Connect iCloud**.
3. Adds and care logs appear on other signed-in iPhones (list refreshes about every 20s; pull to refresh anytime).

## Notes

- GitHub repo private/public does not affect CloudKit sync.
- Public CloudKit DB is the shared team inventory. Tighten later with a private database and CKShare if you need invite-only sharing.
