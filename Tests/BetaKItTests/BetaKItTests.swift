import Foundation
import Testing
@testable import BetaKit

@Test func questionForTodayUsesProvidedQuestionsDeterministically() {
    let questions: [TestFlightFeedbackQuestion] = [
        .init(id: "q1", title: "Q1", helperText: "H1", placeholder: "P1"),
        .init(id: "q2", title: "Q2", helperText: "H2", placeholder: "P2"),
        .init(id: "q3", title: "Q3", helperText: "H3", placeholder: "P3")
    ]

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let date = ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z")!
    let question = TestFlightFeedbackQuestion.questionForToday(
        in: questions,
        calendar: calendar,
        date: date
    )

    #expect(question.id == "q2")
}

@Test func questionForTodayFallsBackToDefaultsWhenQuestionsAreEmpty() {
    let question = TestFlightFeedbackQuestion.questionForToday(in: [], date: .now)
    #expect(TestFlightFeedbackQuestion.defaultQuestions.contains(question))
}

@Test func analyticsManagerUsesConfiguredHandler() async {
    let box = CaptureActor()

    AnalyticsManager.configure { event, info in
        Task {
            await box.update(event: event, info: info)
        }
    }
    defer { AnalyticsManager.reset() }

    AnalyticsManager.logEvent("Test.Event", info: ["key": "value"])

    await box.waitUntilUpdated()
    let event = await box.event
    let info = await box.info
    #expect(event == "Test.Event")
    #expect(info["key"] == "value")
}

@Test func betaContentViewModelStoresConfiguration() {
    let customQuestions: [TestFlightFeedbackQuestion] = [
        .init(id: "custom", title: "Custom", helperText: "Help", placeholder: "Place")
    ]
    let profileURL = URL(string: "https://example.com/dev.png")
    let vm = BetaContentViewModel(
        feedbackQuestions: customQuestions,
        developerProfileImageURL: profileURL,
        allowsFeedbackPasteboardExport: true,
        feedbackContextProvider: { ["build": "42"] }
    )

    #expect(vm.feedbackQuestions == customQuestions)
    #expect(vm.developerProfileImageURL == profileURL)
    #expect(vm.allowsFeedbackPasteboardExport)
    #expect(vm.feedbackContextProvider()["build"] == "42")
}

private actor CaptureActor {
    private var _event: String?
    private var _info: [String: String] = [:]

    var event: String? { _event }
    var info: [String: String] { _info }

    func update(event: String, info: [String: String]) {
        _event = event
        _info = info
    }

    func waitUntilUpdated(maxWaitNanoseconds: UInt64 = 500_000_000) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while _event == nil {
            let now = DispatchTime.now().uptimeNanoseconds
            if now - start >= maxWaitNanoseconds { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
