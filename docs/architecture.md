# Gardens architecture

## Layers

| Layer | Location | Rules |
| --- | --- | --- |
| Domain | `GardensCore` | Pure Swift + Foundation. Models, matching, compact QR, repository protocols. No UIKit/SwiftUI/SwiftData. |
| Persistence (iOS) | `Gardens/…/Persistence` | SwiftData entities map to/from domain types. Implements `PlantRepository`. |
| Platform (iOS) | `Gardens/…/Platform` | Core Image QR rendering, UIKit AirPrint. |
| UI (iOS) | `Gardens/…/Views` | SwiftUI screens only. |

Future Android/web apps should depend on the same domain concepts (or a KMP/TS port of `GardensCore`) and supply their own repository + QR/print adapters.

## Catalog vs instance

- **Catalog** (`PlantCatalogItem`): plant *type* — name, genus, care profile.
- **Instance** (`PlantInstance`): one physical plant — photo, vendor, date arrived, `catalogItemID`.
- Intake matches name+genus (case/whitespace-insensitive) and **reuses** the catalog row when found.

No store-location field.

## QR (two layers)

Wire format: compact JSON with short keys, schema `v=1`:

```
gardens://plant/<instance-uuid>?n=Snake%20Plant
```

| Part | Meaning |
| --- | --- |
| `gardens://` | Magic scheme — identifies a Gardens label; Camera can open the app |
| `plant/<uuid>` | Instance ID → full record in the data store |
| `n=` | Optional offline display name |

Legacy JSON payloads still decode. Care/history are **not** in the QR; they load via `PlantRepository.destination(for:)`.
