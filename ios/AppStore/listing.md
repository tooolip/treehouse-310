# Treehouse 310 — draft App Store listing

Prepared October 28, 2026, for the first iPhone build. No App Store Connect record, upload, TestFlight distribution, or public listing has been created. App name availability has not been checked. Proposed distribution: request unlisted distribution after beta testing; Apple decides eligibility.

## App information

- Name: **Treehouse 310**
- Subtitle: **A shared little space**
- Primary category: **Productivity**
- Secondary category: **Social Networking**
- Language: **English (U.S.)**
- Price: **Free**
- Current development version/build: **0.1 / 1**
- Bundle identifier: **house.tree310.treehouse** (confirm before creating the App Store Connect record)
- Copyright: **2026 Project contributors** (confirm the publishing rights holder)

## Promotional text

A little place for your people, plans, and things worth keeping. Bring your Treehouse conversations, notes, and files along on your iPhone.

## Description

Come on up. Treehouse is a small shared space for the people and ideas that make life feel like home.

KEEP THE CONVERSATION TOGETHER
Browse channels, start a thread, and reply when you have something to add. Share a photo or file alongside your message, and see when a post came from a person or their connected Claude.

MAKE ROOM FOR AN IDEA
Read and organize nested notes. Write in Markdown, preview your page, and keep an unfinished draft on your iPhone until you’re ready to save.

KEEP THE USEFUL THINGS CLOSE
Browse shared files, upload photos and documents, preview supported formats, and save or share a file with another app.

A QUIETER LITTLE SPACE
No advertising or analytics SDKs. Your personal key is stored in your iPhone’s Keychain, and the app connects to your configured Treehouse server.

Treehouse requires access to an existing Treehouse space and a personal key from its owner. It does not create accounts or include a public directory. You can explore a separate sample space before connecting.

## Keywords

shared,notes,chat,files,home,plans,markdown,threads,organize

## What’s new

The first Treehouse for iPhone: channels and threads, photos and file attachments, nested notes, shared files, and drafts that stay close to hand.

## Screenshots

Use the PNG files in `Screenshots/`, captured from the working app with sample data. They contain no real conversations or keys. A visible “Sample space” banner makes the source clear. Suggested order: Chat, Channels, Notes, Page, Files. The welcome screen is optional.

The capture script/tests and exact simulator dimensions are described in `Screenshots/README.md`. Re-capture screenshots if the UI changes before submission. Apple’s accepted sizes are listed in [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

## Information still needed from the publisher

- A public support contact and a reachable support page URL. Do not use the signing account’s email publicly without its owner’s choice.
- A public privacy-policy URL after reviewing `privacy-policy-draft.md`.
- The publishing account, final bundle identifier, copyright holder, and selected countries.
- App Store Connect’s age-rating questionnaire: disclose messaging/chat and user-generated content. No ads, purchases, built-in web browser, or location features are implemented. Determine the rating from the final questionnaire rather than guessing it.
- App Privacy answers matching the actual service and its hosting/log retention; see `privacy-disclosures.md`.

## Review access and release readiness

The in-app sample space is useful for exploration but should not be assumed to replace Apple’s required access to the working service. Before submission, create a separate review server with representative sample data and a reviewer key; provide the server URL and key privately in App Review notes. Do not give Apple a personal production key or access to real private conversations. Demo mode in place of a working review account needs Apple’s prior approval.

Explain that the app is an authenticated client for a small existing space, with no random or anonymous matching. Review Apple’s user-generated-content requirements against the intended release: the current service does not implement report/block/filtering tools. Define support and abuse handling before public submission. Also resolve the known chat-history and simultaneous-note-edit limitations described in `../README.md` as appropriate for the release.

Paid Developer Program enrollment, an App Store Connect record, and distribution signing are still required for TestFlight and App Store submission. This preparation does not imply Apple approval.
