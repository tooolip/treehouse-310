# Treehouse privacy policy — draft for publisher review

Draft date: October 28, 2026. This is a preparation document, not a published policy. Before publication, identify the service operator and support contact, confirm infrastructure logging and backup retention, and replace the unresolved retention details below with the operator’s actual practices.

## What Treehouse does

Treehouse is a shared space for conversations, notes, and files. The iPhone app connects to the Treehouse server you choose. People and connected agents with access to that space can read its shared content. It is not an end-to-end encrypted messaging service.

## Information used by the app and service

When you connect, the app sends your personal access key to your chosen server to identify you. The app stores that key in the iPhone’s Keychain. It does not include the key in URLs or ordinary app preferences.

The server receives and stores the messages, notes, photos, and other files you submit, together with associated names/identifiers, authorship, timestamps, file metadata, and read positions. This information is used to authenticate you, operate the shared space, and make its content available to authorized participants and their connected agents.

The iPhone app has no advertising or analytics SDKs and does not request tracking permission. It does not request access to your contacts, location, microphone, or entire photo library. System photo and file pickers let you choose the items you want to share. Content you choose can contain personal information or embedded metadata.

## Hosting and connected services

The default Treehouse server uses Cloudflare Workers, D1, and R2. Its operator and infrastructure provider process requests to deliver and maintain the service. Network/infrastructure logs may contain technical request information. The operator must confirm the categories, access controls, and retention periods before publishing this policy.

People may connect their own agents to Treehouse. Those agents can read shared content using the access provided by their owners, and their providers may process it under separate policies. The iPhone app itself does not send content directly to an AI provider. A custom Treehouse server may have different operators and practices; ask its owner for its policy.

## Local storage and deletion

The app stores recent content and text drafts in an app-owned directory with iOS data protection and excludes that directory from device backups. Downloaded previews are stored temporarily in the app’s sandbox. Signing out removes the app’s key, drafts, cached content, and temporary previews. Files you explicitly export or share to another app are controlled by that destination and are not removed by signing out.

Shared notes and files can be deleted through Treehouse. Their deletion affects the shared space. The current service does not expose message deletion or account deletion through the iPhone app; contact the operator for those requests. The operator must define how long server backups and logs retain deleted data and how deletion requests are handled before publishing this policy.

## Contact

Publisher/operator and contact channel: **to be supplied by the publisher before publication**. The support page and policy must provide a working contact method for privacy and deletion questions.
