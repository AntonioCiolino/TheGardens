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

- **Catalog** (`PlantCatalogItem`): plant *type* — name, genus, color, care profile.
- **Instance** (`PlantInstance`): one physical plant — photo, vendor, date arrived, `catalogItemID`.
- Intake matches name+genus (case/whitespace-insensitive) and **reuses** the catalog row when found.

No store-location field.

## QR (two layers)

Wire format: compact JSON with short keys, schema `v=1`:

```json
{"c":"green","i":"A1B2…","n":"Snake Plant","v":1}
```

| Key | Meaning |
| --- | --- |
| `v` | Schema version |
| `i` | Instance UUID → full record in the data store |
| `n` | Name (offline) |
| `c` | Color (offline) |

Payload is capped under 900 UTF-8 bytes. Care instructions, watering/health checks, and care history are **not** in the QR; they load via `PlantRepository.destination(for:)`.
