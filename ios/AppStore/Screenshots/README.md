# Capture iPhone screenshots

Generate fresh screenshots from the sample space after changing demo content. Previous images were removed during the public privacy cleanup.

Run the UI tests against a suitable iPhone simulator and export the attachments:

```sh
xcrun xcresulttool export attachments --path build/TreehouseTests.xcresult --output-path build/ExportedScreenshots
```

Review each image for names, keys, server addresses, and private content before publishing it. These are preparation assets; no App Store listing has been submitted by this repository.
