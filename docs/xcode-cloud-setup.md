# Xcode Cloud setup for Gardens

Build and distribute the real iOS app from Apple’s cloud (not this Linux agent).

Repo: [AntonioCiolino/TheGardens](https://github.com/AntonioCiolino/TheGardens)  
Scheme: **Gardens** (shared)  
Bundle ID: `com.gardens.intake`  
Project path: `Gardens/Gardens.xcodeproj`

## Before you start

1. **Apple Developer Program** membership (paid).
2. Mac with **Xcode 15+** — **required once** to turn on Xcode Cloud for this project (Apple’s rule).
3. GitHub repo access (already public/private as you prefer).
4. In Developer portal: App ID `com.gardens.intake` with **iCloud → CloudKit** and container `iCloud.com.gardens.intake`.

### No Mac right now? (web-only)

Apple: the **first** Xcode Cloud setup must be done in **Xcode on a Mac**. After that, you can start builds and edit workflows in **App Store Connect on the web** (Safari on iPhone is fine).

What you can do from the phone **today**:

1. Safari → [App Store Connect](https://appstoreconnect.apple.com/) → **My Apps** → **+** → New App  
   - Platform: iOS  
   - Bundle ID: `com.gardens.intake` (create the ID under Certificates, Identifiers & Profiles if needed)  
   - Name: Gardens  
2. Keep using the **web UI demo** for layout/Sync flows until you can borrow a Mac for ~15 minutes to run **Product → Xcode Cloud → Create Workflow**.
3. After that one Mac session, return to App Store Connect → your app → **Xcode Cloud** to start builds / TestFlight from the web.

There is no supported way to finish the *first* Xcode Cloud grant entirely in the browser.

## 1. Open the project

```text
Gardens/Gardens.xcodeproj
```

- Signing → your **Team** (Automatic).
- Confirm scheme **Gardens** is selected and **Shared** (checked in Manage Schemes).

## 2. Create the Xcode Cloud workflow

1. Xcode → **Product → Xcode Cloud → Create Workflow…** (or the Report navigator → Cloud).
2. Product: **Gardens**.
3. Connect **GitHub** → grant access to `AntonioCiolino/TheGardens` when asked.
4. Start condition: **Branch Changes** on `main` (or “On every pull request” later).
5. Actions:
   - **Archive** → iOS → (optional) **TestFlight Internal Testing** when you’re ready.
6. Environment: latest stable Xcode / macOS recommended.

Xcode Cloud will push a small config commit / use App Store Connect under the hood.

## 3. App Store Connect

1. [App Store Connect](https://appstoreconnect.apple.com/) → Apps → **+** → iOS app  
   Bundle ID: `com.gardens.intake`, name e.g. **Gardens**.
2. Users and Access → Xcode Cloud → confirm the GitHub grant if prompted.
3. After the first successful archive, use **TestFlight** to install on your iPhone.

## 4. First build checklist

- [ ] Workflow created; GitHub connected  
- [ ] App record exists in App Store Connect  
- [ ] CloudKit container enabled on the App ID  
- [ ] Push to `main` (or Start Build manually)  
- [ ] Build green in Xcode → Cloud / App Store Connect → Xcode Cloud  
- [ ] TestFlight install → Sync → Connect iCloud → Write test plant  

## Notes

- `ci_scripts/ci_post_clone.sh` resolves the local `GardensCore` package after clone.
- Signing stays **Automatic**; Xcode Cloud manages certificates for the team.
- The web demo (`ui-preview`) is unrelated — Xcode Cloud only builds the iOS app.
