# The Gardens Experience

Guest app. Scheme **Experience** in `TheGardens.xcworkspace` (or open `Experience/Experience.xcodeproj`). On the device the name is **The Gardens Experience**.

- Bundle ID: `com.gardens.experience`
- CloudKit container: `iCloud.com.gardens.experience` (public database). This is not the Intake container.
- Any guest can publish a caption and a photo. There is no admin check in this scaffold.
- A scan reads one plant from the Intake container `iCloud.com.gardens.intake` (public database, fetch by record id). The guest app does not write those records. The last plants you open stay in SwiftData for offline.
- Offline: SwiftData keeps the last pull, and posts made without iCloud stay on the phone until they upload.
- Logo: `AppIcon.png`, `BrandMark.png`, and `QRMonogram.png` are copies of the Intake assets. The welcome and the feed header show `BrandMark`.

## Apple Developer

1. App ID `com.gardens.experience`.
2. iCloud → CloudKit → container `iCloud.com.gardens.experience`.
3. Signing team on the Experience target.

Record types the app creates:

| Record type | Record name | Fields |
| --- | --- | --- |
| `FeedManifest` | `visit-feed` | `postIDs` (String list; omitted until the first post) |
| `VisitPost` | the post UUID | `id`, `text`, `authorName`, `createdAt`, `image` (Asset, optional) |
| `VisitPost` | `message-of-the-day` | Jen’s note. Edit `text`. `authorName` is Jen. This id is not in `postIDs`. |
| `GardenCatalog` | `garden-places` | `placesJSON`, the fence list. Same shape as the seed file. |

Public database, default zone, one record per save. Same limit as Intake: no change-token fetch, no atomic batch.

CloudKit Console → Schema → Security Roles, Development:

- **World**: Read
- **Authenticated**: Create
- **Creator**: Read and Write

on `VisitPost`, `FeedManifest`, and `GardenCatalog`.

Jen’s note and the fence list are edited in CloudKit Console, public database of `iCloud.com.gardens.experience`. The copy in the app is only the first seed, used when that record does not exist yet, and the last copy kept on the phone when iCloud is unreachable.

## Places

The live fence list is record `garden-places`, field `placesJSON`. `Experience/Experience/Resources/garden-places.json` is written there once, if the record is missing. Later edits belong in the console. One circle per enabled place. iOS watches at most 20. The app does not run continuous GPS.

Radius is 100 meters, the smallest size region monitoring treats as reliable. Home and The Gardens are about 190 meters apart, so these circles stay on different buildings and only meet at the edges. A larger radius will overlap them. The welcome names whichever place was entered.

| Place | Enabled | Center | Source |
| --- | --- | --- | --- |
| Home | yes | 39.1290784, -84.4746211 | 2728 Hackberry Street, Cincinnati, OH 45206. OpenStreetMap building way 83428193 via Nominatim. Testing only. |
| The Gardens | yes | 39.1289487, -84.4768209 | 2800 Woodburn Avenue, Cincinnati, OH 45206. OpenStreetMap building way 1473478916 via Nominatim. Indoor primary space. |
| The Garden Park | no | none | Outdoor lot with no street address. Left off so it is not given the Woodburn or Hackberry pin. Public write-ups of The Gardens describe outdoor greenery at the Woodburn venue and do not identify a separate lot. Add `latitude` and `longitude`, then set `enabled` to true. The welcome already uses the place name. |

Arrival uses Always location and the location background mode so the system can deliver the enter event when the app is not in front. Outside every fence, the splash has no place greeting. Inside, the splash says we’re glad you’re here and names the place. For now that plays on each launch while you are inside.

## Run

1. Open `TheGardens.xcworkspace`.
2. Scheme **Experience**. iPhone or iPad.
3. The `…` menu → **Preview welcome** shows the bounce without standing in a fence.
4. Post from the plus button. With iCloud, the post is a `VisitPost`. Without iCloud, it stays on the phone and is marked waiting to sync.
