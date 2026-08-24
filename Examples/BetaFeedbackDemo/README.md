# BetaFeedbackDemo

This SwiftUI host resolves `BetaFeedbackKit` from the local repository using
`.package(path: "../..")`. It exercises the real feedback sheet, on-device clarification,
developer context, report preparation, and pasteboard export without changing another app's
package lockfile.

To generate the installable iPhone project, run:

```sh
xcodegen generate --spec project.yml
```

To run the macOS Swift package directly:

```sh
swift run BetaFeedbackDemo
```

Choose **Give feedback about this screen**, enter the suggested settings-structure feedback,
and verify the model returns no follow-up. Then try a vague report such as “This section is hard
to use” and verify the model asks one question in its own words.

On iPhone, choose **Start notification feedback** to request notification access and schedule the
first reply notification. Taking a screenshot exercises the same `.onScreenshot` path. The demo
owns the notification-center delegate and forwards BetaFeedbackKit banners and responses.

The on-device clarification path requires a supported OS with Apple Intelligence available.
When the model is unavailable, the package intentionally prepares the original response without
a clarification.
