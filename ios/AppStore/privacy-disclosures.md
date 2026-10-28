# Draft privacy disclosures and release notes

The app sends content to a shared server that retains it. Do not select “Data Not Collected” merely because the iOS app has no analytics SDK. Confirm these proposed answers in App Store Connect against the final app and the server operator’s actual practices.

| Data type | Why | Linked to user | Tracking |
| --- | --- | --- | --- |
| User ID | Identify the person associated with a key and attribute shared activity | Yes | No |
| Emails or Text Messages | Shared chat messages and their metadata | Yes | No |
| Photos or Videos | Images and media deliberately uploaded by the user | Yes | No |
| Other User Content | Notes, documents, filenames, descriptions, and other uploaded files | Yes | No |

These four types are declared for app functionality in `Treehouse/PrivacyInfo.xcprivacy`. The client does not implement advertising, cross-app tracking, contact import, location collection, or a third-party analytics SDK. The data users voluntarily put in files or messages can include other information; confirm whether any additional structured collection or service practices require disclosures. Review Cloudflare observability and any operator-added logging before finalizing diagnostics/usage disclosures. Do not promise a retention period that has not been confirmed.

No required-reason API categories have been intentionally used in this first build; the manifest’s accessed-API list is empty. Recheck it when dependencies or storage/telemetry APIs change. HTTPS and Keychain use system encryption; the Info.plist declares no non-exempt encryption. Confirm export-compliance answers for the final binary and distribution territories.

References: [Apple data type definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatype), [Collection purposes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes/nsprivacycollecteddatatypepurposes).

## TestFlight “What to Test” text

Connect with your personal Treehouse key, or explore the separate sample space. Try posting a message, replying in a thread, attaching a photo, creating/editing a note, and downloading or sharing a file. Put the app in the background while writing, then return and check that your text draft remains. Report the screen, action, expected result, and any error text; never include your key in feedback or screenshots.

Known limits: no push notifications; recent chat is limited by the server’s 200-message window; avoid simultaneous edits to the same note; pending attachment bytes are not restored after an app restart. Do not use production notes for destructive testing.

## Review notes template

Treehouse is an iPhone client for an existing private shared space with channels, threaded messages, nested Markdown notes, and files. There is no anonymous matching or in-app account creation. To review the working service, open Connection settings on the welcome screen and enter the review server origin provided in the private App Review information, then paste its reviewer key. The sample space is also available from “Take a look around,” operates entirely on-device, and is labeled in the interface.

Before using these notes, provision the isolated review server and add its actual credentials in App Store Connect. The current production service supports only its existing two people and should not be used for review access.
