# BetaKit

BetaKit is an open source SwiftUI package focused on one job: helping TestFlight beta testers share better feedback.

## Why BetaKit
Many testers want to help but skip feedback because it is too much work in the moment. BetaKit adds lightweight prompts and screenshot-aware nudges so users can submit useful feedback quickly.

https://github.com/user-attachments/assets/df578175-e59d-4e6d-a626-9c5ac92e43aa

## Current capabilities
- TestFlight feedback prompt sheet with rotating daily question
- Screenshot tip flow to guide users to TestFlight's built-in feedback path
- Customize prompts per screenshotted view for faster feedback
- Hotswappable analytics sink (Optional copy-to-pasteboard button for response + context sharing)
- SwiftUI-first API that can be embedded in existing views or use the `.beta` modifier

## Requirements
- iOS 17+
- macOS 14+
- Swift 6.2+

## Installation (Swift Package Manager)
Add this package to your app in Xcode using the repository URL.

## Quick start
```swift
import SwiftUI
import BetaKit

struct ContentView: View {
    @State private var viewModel = BetaContentViewModel(
        feedbackQuestions: [
            .init(
                id: "first_impression",
                title: "What felt most confusing in this build?",
                helperText: "One short sentence is enough.",
                placeholder: "E.g. \"I couldn't find where to start\""
            ),
            .init(
                id: "what_helped",
                title: "What worked better than expected?",
                helperText: "Call out one thing.",
                placeholder: "E.g. \"Onboarding felt much clearer\""
            )
        ],
        developerProfileImageURL: URL(string: "https://your-cdn.dev/profile.jpg"), // can be your GitHub profile picture if you'd like
        allowsFeedbackPasteboardExport: true,
        feedbackContextProvider: {
            [
                "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            ]
        }
    )

    var body: some View {
        Text("HomeView")
            .beta(
                viewModel: viewModel,
                backgroundMaterial: .thickMaterial,
                foregroundCardStyle: .blue,
                screenshotPromptTitle: "Did this screen behave how you expected?",
                screenshotPromptSubtitle: "Take a screenshot and include one sentence about what happened."
            )
            .task {
                AnalyticsManager.configure { event, info in
                    // Forward into your analytics provider.
                    print("Analytics:", event, info)
                }
                viewModel.setup()
            }
    }
}
```

You can leave `feedbackQuestions` unset to use `TestFlightFeedbackQuestion.defaultQuestions`.
If `developerProfileImageURL` is set, sheets will render your remote profile image next to the app icon.

## Deep links for sheet presentation
`BetaKit` supports deep links so host apps can open sheets from notification taps, debug tools, or internal routing.

Supported hosts:
- `yourapp://beta-feedback` opens the TestFlight feedback question sheet.
- `yourapp://beta-screenshot-tip` opens the screenshot guidance sheet.

In your app's URL router:
```swift
.onOpenURL { url in
    if viewModel.handleDeepLink(url) {
        return
    }
    // Handle your other app links.
}
```

When using local notifications, route tap actions into these deep links (or call `handleDeepLink` directly) so the expected `BetaKit` sheet appears.

## Development
```bash
swift build
swift test
```

## Foreground notification behavior (important)
`BetaKit` schedules local notifications for screenshot tips and daily feedback prompts. If your app is active, iOS can suppress visible banners unless your app opts in to foreground presentation.

In your host app:
1. Set `UNUserNotificationCenter.current().delegate`.
2. Implement `userNotificationCenter(_:willPresent:withCompletionHandler:)`.
3. Return presentation options like `.banner`, `.list`, and `.sound`.

Example:
```swift
import UserNotifications

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
```

Without this, screenshot-tip notifications may be scheduled but not visibly shown while your app stays open.

## License
MIT
