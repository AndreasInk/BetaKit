//
//  TestFlightFeedbackQuestion.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//


import Foundation

public struct TestFlightFeedbackQuestion: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let helperText: String
    public let placeholder: String

    public init(id: String, title: String, helperText: String, placeholder: String) {
        self.id = id
        self.title = title
        self.helperText = helperText
        self.placeholder = placeholder
    }
}

public extension TestFlightFeedbackQuestion {
    static var defaultQuestions: [Self] {
        [
            .init(
                id: "openReason",
                title: "What made you open WalkLock today?",
                helperText: "One sentence is perfect.",
                placeholder: "E.g. \"I needed a nudge to keep walking\""
            ),
            .init(
                id: "feelNow",
                title: "How did WalkLock feel when you used it just now?",
                helperText: "One sentence is perfect.",
                placeholder: "E.g. \"It felt calm and motivating\""
            ),
            .init(
                id: "goalNow",
                title: "What’s the main thing you’re trying to do with WalkLock right now?",
                helperText: "One sentence is perfect.",
                placeholder: "E.g. \"Stay focused on short walks\""
            )
        ]
    }

    static func questionForToday(
        in questions: [Self],
        calendar: Calendar = .current,
        date: Date = .now
    ) -> Self {
        let source = questions.isEmpty ? defaultQuestions : questions
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let index = (dayOfYear - 1) % source.count
        return source[index]
    }
}
