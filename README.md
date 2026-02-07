# BetaKit

BetaKit is an open source SwiftUI package focused on one job: helping TestFlight beta testers share better feedback.

## Why BetaKit
Many testers want to help but skip feedback because it is too much work in the moment. BetaKit adds lightweight prompts and screenshot-aware nudges so users can submit useful feedback quickly.

## Current capabilities
- TestFlight feedback prompt sheet with rotating daily question
- Screenshot tip flow to guide users to TestFlight's built-in feedback path
- Hotswappable analytics sink via `AnalyticsManager.configure`
- Optional copy-to-pasteboard button for response + context sharing
- SwiftUI-first API that can be embedded in existing views

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
        developerProfileImageURL: URL(string: "https://your-cdn.dev/profile.jpg"),
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

## Project goal
Build a reusable SwiftUI package that increases both the quantity and quality of TestFlight feedback for indie and small app teams.

## Development
```bash
swift build
swift test
```

## License
MIT
