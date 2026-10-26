# Gardens architecture

## Layers

| Layer | Location | Rules |
| --- | --- | --- |
| Domain | `GardensCore` | Pure Swift + Foundation. Models, matching, compact QR, repository protocols. No UIKit/SwiftUI/SwiftData/CloudKit. |
| Persistence (iOS) | `Gardens/…/Persistence` | SwiftData entities. Local-only `PlantRepository` fallback. |
| Sync (iOS) | `Gardens/…/Sync` | **CloudKit** shared inventory + iCloud account check. |
| Platform (iOS) | `Gardens/…/Platform` | Core Image QR, AirPrint, T50M Bluetooth labels, camera scanner. T50M label size is a first guess (240×200 pt, centered on the 384-dot head) until a test print. |
| UI (iOS) | `Gardens/…/Views` | SwiftUI; talks to `GardensSession` / `PlantRepository`. |

## Catalog vs instance

- **Catalog** (`PlantCatalogItem`): plant *type* — name, genus, care profile.
- **Instance** (`PlantInstance`): one physical plant — photo, vendor, date arrived, `catalogItemID`.
- Intake matches name+genus and reuses the catalog row when found.
- Deleting the last physical plant of a type removes that catalog record. Existing type only lists types that still have a plant.

No store-location field.

## Sync model (CloudKit)

When the iPhone has an iCloud account:

| Record type | One record = |
| --- | --- |
| `CatalogItem` | Plant type |
| `PlantInstance` | Physical plant (`photo` CKAsset) |
| `CareEvent` | Care / health update |

Container: `iCloud.com.gardens.intake` (public database for shared team inventory).

Without iCloud, the app uses on-device SwiftData only.

## QR

```
gardens://plant/<instance-uuid>?n=Snake%20Plant
```

Care/history are not in the QR; they load via `PlantRepository.destination(for:)`.
