# Gardens

iOS plant intake app (SwiftUI) with a shared `GardensCore` package. Inventory can stay on-device (SwiftData) or sync **record-by-record** across team iPhones via **Apple CloudKit / iCloud**.

No Google login. No Firebase. Staff need an **Apple ID signed into iCloud** on each iPhone.

## Open & run

1. On a Mac, open `Gardens/Gardens.xcodeproj` in Xcode 15+.
2. Set your Development Team under Signing (CloudKit entitlement enabled).
3. Run on an iPhone signed into iCloud.
4. For shared sync setup, see **[docs/cloudkit-setup.md](docs/cloudkit-setup.md)**.

## What’s included

- **Catalog vs instance** — plant types reused by name+genus; each physical plant is its own instance.
- **Intake** — new or existing type; quantity creates N unique instances + batch QR print.
- **Scan + care log** — QR lookup, maintenance / watering / health observations.
- **Team sync** — CloudKit records + photo assets; iCloud account required.
- **Local fallback** — SwiftData when iCloud isn’t available.
- **Compact QR** — `gardens://plant/<uuid>` deep links.

## Layout

```
GardensCore/     Shared models + QR + PlantRepository protocol
Gardens/         iOS app (SwiftUI, SwiftData, CloudKit, camera, print)
docs/            Architecture + CloudKit setup
```

No store-location field (intentionally omitted).
