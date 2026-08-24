//
//  TestFlightScreenshotTipView.swift
//  BetaFeedbackKit
//
//  Created by Andreas Ink on 2/6/26.
//


import SwiftUI

struct TestFlightScreenshotTipView: View {
    @Environment(BetaContentViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                ProfileStackView(
                    appIcon: true,
                    remoteProfileURL: vm.developerProfileImageURL,
                    fallbackImageNames: ["andreas_pfp"],
                    size: 54,
                    overlap: 16
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Thank you for testing :)")
                        .font(.title3.weight(.semibold))
                    Text(introText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                PromptCardView(background: AnyShapeStyle(Color.promptSecondaryBackground), cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Take a screenshot whenever something feels off or great.")
                            .font(.headline)
                        Text(nextStepText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    vm.setHasSeenTestFlightScreenshotTip(true)
                    vm.dismissPresentedSheet()
                    dismiss()
                } label: {
                    Text("Got it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BetaButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
    }

    private var introText: String {
        if vm.feedbackNotificationMode == .onScreenshot {
            "After your next screenshot, I’ll send a notification so you can tell me what you noticed."
        } else {
            "When you take a screenshot, iOS lets you share beta feedback directly. I’ll send a reminder after your next screenshot in the app."
        }
    }

    private var nextStepText: String {
        if vm.feedbackNotificationMode == .onScreenshot {
            "Press and hold the notification, then tap Reply. The app may ask one optional follow-up before preparing a report for TestFlight."
        } else {
            "After the screenshot, you’ll see the iOS preview with share options."
        }
    }
}

private extension Color {
    static var promptSecondaryBackground: Color {
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

#Preview {
    TestFlightScreenshotTipView()
        .environment(BetaContentViewModel())
}
