# Backlog: Universal Links (Camera → Gardens)

**Status:** Parked  
**Priority:** Later  
**Surface:** iOS deep linking + hosting on existing Wix site

## Goal

When someone scans a plant QR with the iPhone **Camera** app, iOS should open **Gardens** directly (Universal Link), not only via the custom scheme `gardens://`.

## Current state

- QR payloads use `gardens://plant/<instance-uuid>?n=<name>`.
- App handles that scheme via `CFBundleURLTypes` + `onOpenURL`.
- That works once Gardens is installed and the user confirms “Open in Gardens,” but it is **not** a true Universal Link.

## Required work

1. **Host** `apple-app-site-association` (AASA) at:
   ```
   https://<domain>/.well-known/apple-app-site-association
   ```
   - HTTPS, **no redirect**
   - `Content-Type: application/json` (or `application/pkcs7-mime`)
   - No file extension on the URL path

2. **AASA contents** (fill in Team ID):
   ```json
   {
     "applinks": {
       "apps": [],
       "details": [
         {
           "appID": "TEAMID.com.gardens.intake",
           "paths": ["/plant/*"]
         }
       ]
     }
   }
   ```

3. **Xcode:** Associated Domains entitlement `applinks:<domain>`.

4. **QR / core:** Encode `https://<domain>/plant/<uuid>` (keep parsing `gardens://` and legacy UUID/JSON for older labels).

5. **App:** Handle `https` plant URLs the same as today’s `gardens://` deep link (open instance + care sheet).

## Wix note

Wix often cannot serve a clean `/.well-known/` file (redirects / wrong content type). Preferred approach if Wix blocks AASA:

- Host AASA on a subdomain (Cloudflare / GitHub Pages / tiny static host), e.g. `app.<domain>`
- Point Universal Links + QR codes at that subdomain
- Do **not** rely on Wix Media Manager URLs

## Inputs still needed from owner

- [ ] Exact domain (or subdomain) to use
- [ ] Apple Developer **Team ID**
- [ ] Confirm Wix vs alternate host for AASA

## Acceptance

- [ ] Apple CDN / AASA validator accepts the file
- [ ] Camera scan of a new `https://…/plant/…` QR opens Gardens to that instance
- [ ] Older `gardens://` labels still resolve
- [ ] No change to catalog/instance/care data model

## Out of scope for this ticket

- Android App Links
- Web plant detail page (optional later; AASA only needs a valid path on the domain)
