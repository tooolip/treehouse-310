# First iPhone build verification

Verified October 28, 2026.

- Xcode 27.1 built the iOS 18+ app for the simulator and physical iPhone.
- Development signing used the owner’s free Personal Team; no paid enrollment or purchase was made.
- Treehouse 0.1 (1), bundle ID `house.tree310.treehouse`, was installed on the connected iPhone. Its code signature verifies, the provisioning profile includes that phone, and the app identifier matches.
- The owner approved macOS signing access, trusted the development profile on the iPhone, and confirmed that Treehouse opens.
- The current development profile expires **November 4, 2026, at 1:40 a.m. America/New_York**. Rebuild and reinstall before/after expiration using the same signing account and bundle identifier. The profile uses the normal free seven-day provisioning period.
- Eleven unit tests and two interface tests passed on the iPhone 18 Pro Max simulator. The interface tests were rerun successfully after the final button-contrast adjustment. Tests exercise posting, replies, reading/editing notes, file preview, and sign-out using isolated sample data.
- The actual Swift API client passed an integration runner against a local Cloudflare Worker using the repository’s local-only test key. It exercised identity, channels, posting/replies, multipart uploads, authenticated file downloads, read acknowledgments, note create/read/update/move/delete, and file deletion.
- The Worker TypeScript type check passed. No Worker business logic or production data was changed, and no production deployment was performed.
- Screenshots were visually reviewed, including the welcome screen, channels, chat, note reader, files, file preview, and dark-mode Settings. Seven final 1320 × 2868 screenshots are in `AppStore/Screenshots/`.
- Listing text, privacy-policy draft, data disclosures, TestFlight testing text, and review-note preparation are in `AppStore/`. Support contact/URLs, policy retention details, release review requirements, and paid distribution setup remain to be completed before publication. No App Store Connect record or TestFlight upload was made.

Production sign-in, production messages, and on-phone photo/document picker behavior still need the owner’s hands-on testing. Enter the existing personal key directly on the phone; no real key was requested or committed here. Push notifications, server pagination, and atomic note-conflict protection are not part of this build. See `README.md` for limits and reinstall instructions.
