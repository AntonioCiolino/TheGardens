# Publishing to TestFlight

Steps to push a build of **The Gardens Experience** (and later **Gardens**) to TestFlight.
Archiving/uploading is an interactive Xcode step that signs with your distribution
credentials and sends the binary to App Store Connect — it is done by hand in Xcode.

## Before you archive

- [ ] **Run destination = Any iOS Device (arm64).** You cannot archive against a simulator.
- [ ] **Active scheme** is the app you're shipping (`Experience` or `Gardens`).
- [ ] **Build number is unique.** Each upload needs a higher `CURRENT_PROJECT_VERSION`
      than the last upload for that app. First upload can stay at build `1`.
- [ ] **CloudKit schema deployed to Production.** TestFlight builds use the CloudKit
      **Production** environment, not Development. For Experience, deploy the
      `FeedReport` record type and the `visit-reports` manifest to Production in the
      CloudKit Console; otherwise report submissions fail (posts still hide locally).

## Archive and upload

1. Xcode toolbar: set run destination to **Any iOS Device (arm64)**.
2. Confirm the scheme (e.g. **Experience**). Archive uses the **Release** config by default.
3. **Product → Archive.** When it finishes, the Organizer opens.
4. Select the archive → **Distribute App → App Store Connect → Upload**.
5. Use **automatic signing**; let Xcode manage the distribution certificate and profile.
6. Xcode validates, then uploads. The build appears under
   **App Store Connect → the app → TestFlight** after a few minutes of processing.

## Share with testers

- **Internal testers** (up to 100, App Store Connect users on the team): no App Review,
  available as soon as processing completes.
- **External testers** (up to 10,000): one lightweight App Review per version.
- Testers install via the **TestFlight** app. Builds expire after 90 days.

## Per-app notes

### The Gardens Experience (public, guest UGC)
- Guideline 1.2 moderation is implemented: per-post report (writes a `FeedReport`
  to CloudKit), block author (local), and a community-guidelines agreement gate
  before the first post.
- `ITSAppUsesNonExemptEncryption = false` is set, so no per-upload encryption prompt.
- For full public App Store release (not just TestFlight) also complete in
  App Store Connect: App Privacy labels (photos, location, user content), a privacy
  policy URL, age rating, screenshots, and App Review notes justifying background
  location (the geofence welcome) and describing the report/block/24h moderation.

### Gardens (internal / staff)
- `ITSAppUsesNonExemptEncryption = false` is set.
- Icon is a distinct dark (cream-G-on-green) variant so staff can tell it apart from
  the light Experience icon.
- Distribute to staff via **internal TestFlight** now; **Apple Business Manager +
  Custom Apps** is the planned longer-term managed path (still a private App Review,
  but no public listing).
