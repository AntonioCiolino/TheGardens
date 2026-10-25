# Gardens

iOS plant intake app (SwiftUI + SwiftData) with a shared `GardensCore` package for future Android/web ports.

## Open & run

1. On a Mac, open `Gardens/Gardens.xcodeproj` in Xcode 15+.
2. Select an iOS 17+ Simulator or device.
3. Set your Development Team under Signing.
4. Run (⌘R).

## What’s included

- **Catalog vs instance** — plant types (`PlantCatalogItem`) are reused by name+genus; each physical plant is a separate `PlantInstance` (photo, vendor, date arrived).
- **Intake** — two modes: **New type** (first arrival) or **Existing type** (add more of a catalog plant). Quantity creates N unique instances.
- **Batch labels** — after save, print all QRs for that arrival (e.g. 7 labels for 7 plants).
- **List + detail** — instances with photos; care above QR; single-label print on detail.
- **Compact QR** — instance ID + short name; care/history load from storage by ID.
- **Print** — AirPrint (PDF preview OK; no physical printer required).

## Layout

```
GardensCore/          Shared models + QR + repository protocols (Foundation only)
Gardens/              iOS app (SwiftUI, SwiftData, Core Image, UIKit print)
  Gardens.xcodeproj
  Gardens/
```

No store-location field (intentionally omitted).
