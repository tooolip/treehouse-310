# Draft iPhone screenshots

Seven unmodified screenshots captured from the running app on the iPhone 18 Pro Max simulator, iOS 27.0, on October 28, 2026. Each PNG is **1320 × 2868** pixels. All content is from the isolated sample space; no personal keys or real conversations appear.

| File | Screen |
| --- | --- |
| `00-welcome.png` | Key entry and sample-space entry |
| `01-channels.png` | Shared channels |
| `02-chat.png` | Threads and message composer |
| `03-notes.png` | Notebook browser |
| `04-page.png` | Native note reader |
| `05-files.png` | Shared file browser |
| `06-file-preview.png` | Text-file preview and sharing |

Suggested store order: 02, 01, 03, 04, 05. These are draft listing assets, not an uploaded listing. The app’s “Sample space” banner remains visible so the provenance is clear.

To reproduce, run the `Treehouse` scheme’s UI tests against an available Pro Max simulator. The tests attach screenshots to the `.xcresult` bundle. Export them with:

```bash
xcrun xcresulttool export attachments \
  --path build/TreehouseProMaxTests.xcresult \
  --output-path build/ExportedScreenshots
```

Match the filenames using the exported `manifest.json`. Re-capture after UI changes, and confirm dimensions against Apple’s [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) before submission.
