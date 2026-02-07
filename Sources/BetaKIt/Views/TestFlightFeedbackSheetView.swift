//
//  TestFlightFeedbackSheetView.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//

import SwiftUI

struct TestFlightFeedbackSheetView: View {
    @Environment(BetaContentViewModel.self) private var vm: BetaContentViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isAnswerFocused: Bool

    @AppStorage("testFlightFeedbackQuestionId") private var storedQuestionId = ""
    @AppStorage("testFlightFeedbackQuestionDay") private var storedQuestionDay = 0

    @State private var answer: String = ""
    @State private var didComplete = false
    @State private var didCopyFeedback = false
    
    private var availableQuestions: [TestFlightFeedbackQuestion] {
        let configured = vm.feedbackQuestions
        return configured.isEmpty ? TestFlightFeedbackQuestion.defaultQuestions : configured
    }

    private var question: TestFlightFeedbackQuestion {
        if let stored = availableQuestions.first(where: { $0.id == storedQuestionId }) {
            return stored
        }
        return TestFlightFeedbackQuestion.questionForToday(in: availableQuestions)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                devIntroHeader

                PromptHeaderView(
                    title: "Quick TestFlight question",
                    subtitle: question.title,
                    titleFont: .title2.weight(.bold),
                    subtitleFont: .callout,
                    titleColor: .primary,
                    subtitleColor: .secondary,
                    spacing: 6
                )
                .padding(.top, 4)

                PromptCardView(background: AnyShapeStyle(Color.promptSecondaryBackground), cornerRadius: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.helperText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextField(question.placeholder, text: $answer, axis: .vertical)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.promptBackground)
                            )
                            .focused($isAnswerFocused)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        submit()
                    } label: {
                        Label("Submit", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(BetaButtonStyle())
                    .disabled(answerTrimmed.isEmpty)

                    if vm.allowsFeedbackPasteboardExport {
                        Button {
                            didCopyFeedback = vm.copyFeedbackToPasteboard(
                                answer: answerTrimmed,
                                questionId: question.id,
                                questionTitle: question.title
                            )
                            if didCopyFeedback {
                                AnalyticsManager.logEvent("TestFlight.Feedback.CopyToPasteboard", info: [
                                    "questionId": question.id,
                                    "screen": "testflight_feedback_sheet"
                                ])
                            }
                        } label: {
                            Label(
                                didCopyFeedback ? "Copied" : "Copy response + context",
                                systemImage: didCopyFeedback ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .disabled(answerTrimmed.isEmpty)
                    }

                    Button("Skip") {
                        markCompleted(reason: "skip")
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .opacity(0.6)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .onAppear {
            ensureQuestionForToday()
            AnalyticsManager.logEvent("TestFlight.Feedback.View", info: [
                "questionId": question.id,
                "screen": "testflight_feedback_sheet"
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isAnswerFocused = true
            }
        }
        .onDisappear {
            if !didComplete {
                markCompleted(reason: "dismiss")
            }
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

    static var promptBackground: Color {
        #if os(iOS)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
}

private extension TestFlightFeedbackSheetView {
    var answerTrimmed: String {
        answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var devIntroHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileStackView(
                appIcon: true,
                remoteProfileURL: vm.developerProfileImageURL,
                fallbackImageNames: ["andreas_pfp"],
                size: 54,
                overlap: 16
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Thank you for testing this :)")
                    .font(.title3.weight(.semibold))
                Text("This is mostly shared with friends, so your quick feedback really helps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func ensureQuestionForToday() {
        let calendar = Calendar.current
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: Date()) ?? 1
        guard storedQuestionDay != dayOfYear || storedQuestionId.isEmpty else { return }
        let todayQuestion = TestFlightFeedbackQuestion.questionForToday(in: availableQuestions)
        storedQuestionDay = dayOfYear
        storedQuestionId = todayQuestion.id
    }

    func submit() {
        guard !answerTrimmed.isEmpty else { return }
        vm.testFlightFeedbackAnswer = answerTrimmed
        vm.testFlightFeedbackQuestionId = question.id
        vm.hasShownTestFlightFeedbackPrompt = true
        didComplete = true

        AnalyticsManager.logEvent("TestFlight.Feedback.Submit", info: [
            "questionId": question.id,
            "answer": answerTrimmed,
            "screen": "testflight_feedback_sheet"
        ])

        dismiss()
    }

    func markCompleted(reason: String) {
        guard !didComplete else { return }
        vm.hasShownTestFlightFeedbackPrompt = true
        didComplete = true
        AnalyticsManager.logEvent("TestFlight.Feedback.Skip", info: [
            "reason": reason,
            "questionId": question.id,
            "screen": "testflight_feedback_sheet"
        ])
    }
}

#Preview {
    TestFlightFeedbackSheetView()
        .environment(BetaContentViewModel())
}
