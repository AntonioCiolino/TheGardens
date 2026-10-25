# Gardens

iOS plant intake app (SwiftUI + SwiftData) with a shared `GardensCore` package for future Android/web ports.

## Open & run

1. On a Mac, open `Gardens/Gardens.xcodeproj` in Xcode 15+.
2. Select an iOS 17+ Simulator or device.
3. Set your Development Team under Signing.
4. Run (⌘R).

## What’s included

- **Catalog vs instance** — plant types (`PlantCatalogItem`) are reused by name+genus; each physical plant is a separate `PlantInstance` (photo, vendor, date arrived).
- **Intake** — **New type** or **Existing type** (reuses stored photo). Quantity creates N unique instances.
- **Batch labels** — print all QRs for an arrival.
- **Scan + care log** — look up a plant by QR/UUID, record maintenance, watering & health observations; saved to care history.
- **List + detail** — photos, care above QR, log care from detail.
- **Compact QR** — instance ID + name; rich data loads by ID.
- **Print** — AirPrint (PDF preview OK).

## Layout

```
GardensCore/          Shared models + QR + repository protocols (Foundation only)
Gardens/              iOS app (SwiftUI, SwiftData, Core Image, UIKit print)
  Gardens.xcodeproj
  Gardens/
```

No store-location field (intentionally omitted).
