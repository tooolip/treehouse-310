# Treehouse for iPhone

A native SwiftUI client for the existing Treehouse JSON API. Requires iOS 18+ and Xcode 16+ (developed with Xcode 27.1). No package manager or third-party iOS dependencies are required.

## Install on your iPhone with a free Apple Account

1. Open `Treehouse.xcodeproj` in Xcode.
2. Sign in at **Xcode → Settings → Accounts** with your Apple Account. Paid Developer Program enrollment is not needed for this installation.
3. Connect and unlock your iPhone, trust the Mac, and enable **Settings → Privacy & Security → Developer Mode** when prompted. The phone may restart.
4. Select the **Treehouse** app target, open **Signing & Capabilities**, and choose your **Personal Team**. Leave automatic signing enabled. If Apple reports the bundle identifier is unavailable, change it to your own unique identifier and update the install script’s launch identifier.
5. Select your iPhone as the run destination and press **⌘R**. If macOS asks `codesign` to use a key, approve the request using your Mac login password. If the phone asks you to trust the developer, follow its on-device instructions.
6. Open Treehouse and paste your existing personal Treehouse key. Replace the example server with your own deployed workspace origin. The key goes directly to that server and is stored in this iPhone’s Keychain.

Use **Take a look around** to try a separate sample space. It contains fictional/sample content and never contacts the server. Leave the demo to sign into the real Treehouse.

To keep personal signing settings out of commits, put `DEVELOPMENT_TEAM = YOUR_TEAM_ID` in `ios/Local.xcconfig` instead of committing a team selection in the shared project. `Signing.xcconfig` includes that ignored file when present; simulator builds and CI work without it.

After the first signing setup, you can rebuild and reinstall from Terminal:

```bash
cd ios
xcrun devicectl list devices
bash scripts/install-device.sh YOUR_DEVICE_ID
```

Free Personal Team provisioning expires after seven days. Rebuild and reinstall using the same account and bundle identifier; do not delete the app if you want to retain its local drafts. Paid enrollment is required for TestFlight and App Store distribution. No push entitlement is used in this build.

Apple references: [Personal Teams and their limits](https://developer.apple.com/help/account/basics/about-your-developer-account), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Build and test

```bash
xcodebuild -project Treehouse.xcodeproj -scheme Treehouse \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

xcrun simctl list devices available
xcodebuild -project Treehouse.xcodeproj -scheme Treehouse \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO test
```

Unit tests cover authentication, encoding, plain-text 401 errors, attachment decoding, date parsing, server character limits, note conflict preflight, draft removal, origin restrictions, and sample-space round trips. UI tests exercise chat, note editing, files, and sign-out. They use only isolated sample data.

`scripts/generate_project.py` recreates the project and shared scheme after adding/removing source files. It moves an existing project-level development team selection into `Local.xcconfig` when that local file does not already exist. The app icon and sample illustration adapt the artwork already present in `public/index.html`.

## Local server integration

From the repository root, install the existing server dependencies with `npm ci`, copy `.dev.vars.example` to `.dev.vars` if you have no existing local variables, apply local migrations, and start Wrangler:

```bash
npx wrangler d1 migrations apply DB --local
npx wrangler dev --local --port 8787
```

In a second terminal, compile the integration runner using the same Core sources as the app:

```bash
xcrun swiftc -parse-as-library -swift-version 5 -D DEBUG \
  ios/Treehouse/Core/*.swift ios/scripts/LocalIntegration.swift \
  -o ios/build/local-integration
ios/build/local-integration
```

This runner uses only `http://127.0.0.1:8787` and the repository’s local test key. It creates a uniquely named local test channel, exercises messages, files, read acknowledgments, and note CRUD, then removes its note and file. Test messages remain in that local channel. Never point it at production.

## First-version boundaries

- Chat polls about every 15 seconds while its screen is active. Background push notifications are not implemented.
- The deployed API returns the latest 200 messages, including replies. Older thread roots may be outside that window. Cursor pagination requires a future server update.
- Marking a channel read is an explicit action in the conversation menu. Posting also marks the channel read according to existing server behavior.
- Message text drafts and note drafts persist locally. Pending attachment bytes and their upload receipts are kept only while the composer remains alive; reselect attachments after restarting the app. Ambiguous message sends require confirmation before retrying.
- Notes check for changed content before saving, but the deployed API cannot guarantee an atomic conditional write. Avoid editing the same note simultaneously. Full Markdown tables and code-block styling are not implemented; raw text remains readable.
- The app caches recent content for offline reading. You must reconnect to send or save; there is no automatic offline write queue. Sign-out removes credentials, drafts, cached content, and previews.
- App Store copy, privacy draft, release notes, and screenshot capture instructions are in `AppStore/`. These are preparation materials; nothing has been uploaded or published.
