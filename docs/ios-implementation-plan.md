# Treehouse iOS implementation plan

Status: initial client implemented October 28, 2026. See `ios/README.md` for the build, tests, Personal Team installation, and current limits. Chat, Notes, Files, Keychain sign-in, local text drafts, sample mode, and draft store materials are implemented. The server changes and push notifications below remain future work. No production server changes have been deployed.

## Recommendation and assumptions

Build a native SwiftUI iPhone app in `ios/` within this repository. Connect directly to `https://workspace.example.com/api/` using URLSession and the existing personal bearer key. Keep the Cloudflare Worker, D1 database, R2 storage, browser UI, and MCP clients sharing the same data and business logic.

Assume the initial audience is Sam and Alex, with feature coverage for Chat, Notes, and Files. Start with iOS 18 or later, subject to checking both people's phones. Make chat the first usable milestone. Use a simulator during development and choose the signing team, bundle identifier, and device distribution approach before installing on phones. TestFlight is the proposed beta route.

Work can happen in this Codex chat. This machine has Xcode 27.1 and the iOS Simulator 27.1 SDK installed. Simulator runtimes, an actual build, and device signing have not yet been verified. Xcode remains useful for previews, debugging, signing, and archives. Its Codex integration is optional; no extension is required to create the project and run command-line builds here.

## Existing integration points

The JSON API in `src/api.ts` already exposes the necessary operations. The iOS app should use it directly; MCP remains the interface for agents.

| Area | Existing endpoints | Client behavior |
| --- | --- | --- |
| Identity | `GET /api/me` | Validate the pasted key and show the returned person. |
| Channels | `GET /api/chat/channels` | List channels, activity, thread counts, and unread counts. |
| Chat | `GET/POST /api/chat/messages` | Read by channel or thread; post text, one file, or both. Replies use `reply_to`. |
| Read state | `POST /api/chat/read` | Update the shared per-person channel read position. |
| Notes | `GET/PUT /api/notes`, `GET /api/notes/read` | Browse nested pages, read Markdown, create and save notes. |
| Note management | `POST /api/notes/move`, `POST /api/notes/delete` | Rename/move pages and explicitly confirm deletion of descendants. |
| Files | `GET/POST /api/files` | List metadata and upload multipart form data. |
| File content | `GET /api/files/{id}/content` | Authenticated download for preview or export. |
| File deletion | `POST /api/files/{id}/delete` | Delete shared files after confirmation. |

Current constraints: 10,000 characters per message, 200,000 per note body, one explicit attachment per message, and 25 MiB per file. Chat responses contain at most 200 messages. The API returns JSON `{ error }` for input errors, but authentication failures are plain-text HTTP 401; the client must handle both.

## App structure

- `ios/Treehouse.xcodeproj`: app, unit-test, and UI-test targets with shared schemes.
- `ios/Treehouse/App`: launch flow, dependency setup, tabs, and scene lifecycle.
- `ios/Treehouse/Core`: Codable API models, API client, Keychain store, authenticated attachment loader, local cache, and draft storage.
- `ios/Treehouse/Features/Auth`, `Chat`, `Notes`, `Files`, and `Settings`: SwiftUI views and observable feature state.
- `ios/TreehouseTests` and `ios/TreehouseUITests`: API fixtures, state tests, and key user journeys.

Use Swift concurrency and observable feature stores with injected services. Start with Apple frameworks and no third-party runtime dependencies. Use an app-owned protected directory for a small Codable cache and drafts; add a database only if cache size or querying warrants one. Keep API response models separate from presentation state. Use stable numeric IDs and support the server's fractional-second UTC timestamps.

## Milestone 1: Project, connection, and identity

Create the Xcode project, app icon placeholder, light/dark themes, and Chat / Notes / Files tabs with Settings access. Implement a production endpoint and a development configuration that cannot accidentally send test writes to production.

The sign-in screen accepts a personal key, validates it with `/api/me`, and stores it in Keychain with device-only accessibility appropriate for foreground use. Never place keys in source, fixtures, logs, analytics, URLs, or ordinary preferences. Attach authorization only to the configured Treehouse origin, including downloads; reject cross-origin credential forwarding. Treat HTTP 401 as requiring reauthentication. Sign-out cancels outstanding work and removes credentials, drafts, cached private data, and temporary previews.

Deliverable: simulator app can sign in with a local test key, restore its session, display identity, handle an invalid key, and sign out.

## Milestone 2: Chat and attachments

Build a channel list with unread badges, a list of top-level threads, thread details, and a composer. Identify human and Claude posts using the existing `author` and `via` fields. Initially treat `web` as a human post; the API currently assigns this value to every human API request. Add a separate `ios` source only if identifying devices becomes a requirement, with coordinated web/MCP compatibility.

Support text-only, file-only, and text-plus-file posts. Pick photos with PhotosPicker and documents with the system importer. Upload the file first and post the returned `file_id`. Keep that ID if message posting fails so retrying does not upload the file again. Show progress, errors, and retained drafts. Do not automatically retry a POST after an ambiguous timeout, because the server currently has no idempotency support.

Fetch protected image bytes with the API client rather than an unauthenticated image URL. Preview images and supported documents from local temporary files; export through the system share sheet. Keep raw HTML and scripts inert. Preserve compatibility with the browser's legacy display of image filenames mentioned in message text; explicit `file_id` remains the primary attachment reference.

Refresh immediately on foreground entry, after posting, on pull-to-refresh, and approximately every 15 seconds while chat is active. Cancel polling in the background, avoid overlapping requests, and discard responses for a previously selected channel. Preserve scroll position and do not jump when the reader is viewing older messages. Persist unsent drafts and show cached content with its last refresh time when offline. Offline writes require an explicit retry after connectivity returns.

Deliverable: Sam and Alex can exchange threads and attachments between the browser and simulator using local development data.

## Milestone 3: Small server improvements for reliable mobile chat

The existing endpoints are enough for the first chat prototype. Before calling chat complete, add the following backwards-compatible capabilities in the shared server logic and JSON API:

1. **Thread history:** add a top-level-thread listing mode with an ID cursor and `has_more`; fetch thread replies separately with their own cursor. Today the 200-message window includes replies, so busy threads can displace their parent from the channel result, and long threads can lose their root. Always load the root separately when needed.
2. **Refresh:** expose a bounded message-ID delta query for new replies/messages, or continue refetching visible pages until delta refresh is justified. Existing MCP `since` and `unread_only` options are not currently forwarded by the JSON API.
3. **Read acknowledgments:** accept an optional `through_id`, validate it belongs to the channel, and monotonically advance the read cursor only through content actually displayed. Current `markRead` advances to the server's latest message and can mark unseen arrivals read. Retain legacy behavior for existing callers; use the new cursor in iOS and update the browser for consistent behavior. Define channel read semantics explicitly for replies inside unopened threads. Existing posting also marks the entire channel read, so review that behavior as part of this change.

Use representative local fixtures with more than 200 messages and heavily active threads. Preserve existing web and MCP callers. Add any schema changes as new numbered migrations.

## Milestone 4: Notes

Build nested browsing, a Markdown reader, plain Markdown editor with preview, create, rename/move, and delete. Preserve unsaved drafts across interruptions. Confirm recursive deletion with the affected page count.

Before enabling collaborative editing, add a server-issued revision and an atomic conditional save with HTTP 409 on conflict. A pre-save fetch alone cannot prevent an overwrite. Prefer a monotonically increasing revision over timestamp equality. Keep compatibility for current clients, then update browser and MCP writes to use revisions as well so every editing path participates. Include the revision in conflict responses and let the user compare/copy the draft or explicitly replace the latest version. Use the same protection for operations that can invalidate an active editor, especially moves and deletes, or explicitly document their semantics.

Deliverable: a draft survives leaving the app, and competing edits produce a visible conflict instead of silently losing changes.

## Milestone 5: Files and beta readiness

Complete file browsing, metadata, photo/document upload, download, supported previews, sharing, and delete. Enforce file-size limits before uploading and use native picking interfaces. Start with one attachment per message to match the server.

Verify Dynamic Type, VoiceOver labels, dark mode, keyboard behavior, empty/loading/error states, slow connectivity, and session revocation. Bound local cache size and clear temporary exports. Verify image uploads and file access on a physical iPhone. Configure signing and produce a beta archive after the signing team and distribution choice are supplied.

Add an iOS build/test job on an available macOS runner. Keep iOS-only changes from triggering the current Worker deployment unnecessarily: `.github/workflows/deploy.yml` deploys on every push to `main` today. Preserve deployment for Worker, public assets, migrations, dependency lockfiles, configuration, and deployment-workflow changes. Never run integration tests against production data.

Deliverable: a signed beta with Chat, Notes, and Files working against the same Treehouse as the web and MCP clients.

## Milestone 6: Push notifications

Treat notifications as a separate backend feature. Foreground polling alone cannot deliver reliable background notifications, and the repository currently has no APNs integration.

Add authenticated device registration/removal, per-person preferences, and APNs credentials stored as server secrets. Generate notification events in shared `postMessage` logic so browser, MCP, and iOS posts all participate. Use durable delivery/retries, discard invalid device tokens, and avoid notifying the sender. Default to minimal lock-screen content. Resolve a tapped notification to the correct channel/thread and then fetch current data through the authenticated API. Revisit Keychain accessibility only if a later background feature needs it.

Acceptance: a message posted from either the browser or MCP reaches the other person's opted-in iPhone when the app is backgrounded; tapping it opens the thread. Signing and APNs configuration are required before device validation.

## Verification and first implementation slice

Run focused Swift tests for request construction, JSON decoding, plain-text 401 handling, fractional timestamps, draft retention, cancellation, and pagination. Run local Worker API tests for cursor boundaries, read acknowledgments, permissions, attachment linking, and note conflicts. Verify browser and MCP compatibility after shared-server changes. Exercise a simulator flow for sign-in, new thread, reply, attachment, note conflict, file export, offline recovery, and sign-out.

Begin with Milestone 1 and text-only Chat from Milestone 2. This creates a useful end-to-end connection before adding attachments, server improvements, notes, and distribution. The existing local Worker setup and test keys in `.dev.vars.example` provide development data without requiring a production key.

## References

- Repository sources: `src/api.ts`, `src/auth.ts`, `src/chat.ts`, `src/notes.ts`, `src/files.ts`, `public/app.js`, migrations, and `.github/workflows/deploy.yml`, reviewed at commit `1826ee8`.
- [Official Codex IDE guidance](https://learn.chatgpt.com/docs/codex/ide): Xcode provides its own Codex integration.
- [Apple Keychain services](https://developer.apple.com/documentation/security/keychain-services).
- [Apple remote notification server guidance](https://developer.apple.com/documentation/usernotifications/setting-up-a-remote-notification-server).
