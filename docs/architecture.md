# Gardens architecture

## Layers

| Layer | Location | Rules |
| --- | --- | --- |
| Domain | `GardensCore` | Pure Swift + Foundation. Models, matching, compact QR, repository protocols. No UIKit/SwiftUI/SwiftData/Firebase. |
| Persistence (iOS) | `Gardens/…/Persistence` | SwiftData entities map to/from domain types. Local-only `PlantRepository` fallback. |
| Sync (iOS) | `Gardens/…/Sync` | Firestore + Storage + Google Sign-In. Shared multi-user `PlantRepository`. |
| Platform (iOS) | `Gardens/…/Platform` | Core Image QR rendering, UIKit AirPrint, camera scanner. |
| UI (iOS) | `Gardens/…/Views` | SwiftUI screens; talk to `GardensSession` / `PlantRepository`. |

Future Android/web apps should depend on the same domain concepts and supply their own repository (also against Firestore).

## Catalog vs instance

- **Catalog** (`PlantCatalogItem`): plant *type* — name, genus, care profile.
- **Instance** (`PlantInstance`): one physical plant — photo, vendor, date arrived, `catalogItemID`.
- Intake matches name+genus (case/whitespace-insensitive) and **reuses** the catalog row when found.

No store-location field.

## Sync model (Firestore)

When `GoogleService-Info.plist` is present and the user signs in with Google:

| Collection / path | One document = |
| --- | --- |
| `workspaces/default/catalog/{id}` | Plant type |
| `workspaces/default/instances/{id}` | Physical plant (`photoPath` → Storage) |
| `workspaces/default/careEvents/{id}` | Care / health update |
| Storage `workspaces/default/photos/{id}.jpg` | Plant photo |

This is **record-level** sync (not a shared file copy). Teammates see each other’s adds and care logs via live listeners.

Without Firebase config (or while signed out), the app uses on-device SwiftData only.

## QR (two layers)

```
gardens://plant/<instance-uuid>?n=Snake%20Plant
```

| Part | Meaning |
| --- | --- |
| `gardens://` | Magic scheme — identifies a Gardens label; Camera can open the app |
| `plant/<uuid>` | Instance ID → full record in the data store |
| `n=` | Optional offline display name |

Legacy JSON payloads still decode. Care/history are **not** in the QR; they load via `PlantRepository.destination(for:)`.
