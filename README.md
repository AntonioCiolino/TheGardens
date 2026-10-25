# Gardens

iOS plant intake app (SwiftUI + SwiftData) with a shared `GardensCore` package for future Android/web ports.

## Open & run

1. On a Mac, open `Gardens/Gardens.xcodeproj` in Xcode 15+.
2. Select an iOS 17+ Simulator or device.
3. Set your Development Team under Signing.
4. Run (⌘R).

## What’s included

- **Catalog vs instance** — plant types (`PlantCatalogItem`) are reused by name+genus; each physical plant is a separate `PlantInstance` (photo, vendor, date arrived).
- **Intake form** — camera / photo library, name, genus, vendor, arrival date, optional care defaults.
- **List + detail** — saved instances with photos; detail shows QR, care guidance, and care history.
- **Compact QR** — embeds instance ID + short name; full care/watering/health/history load from storage by ID.
- **Print** — AirPrint sheet for a label (works with PDF preview; no physical printer required).

## Layout

```
GardensCore/          Shared models + QR + repository protocols (Foundation only)
Gardens/              iOS app (SwiftUI, SwiftData, Core Image, UIKit print)
  Gardens.xcodeproj
  Gardens/
```

No store-location field (intentionally omitted).
