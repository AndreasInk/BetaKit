#if canImport(Evaluations) && canImport(FoundationModels)
import Evaluations
import Foundation
import FoundationModels
import ImageIO
import Testing
@testable import BetaFeedbackKit

@available(iOS 27.0, macOS 27.0, *)
private struct ClarificationQuestionEvaluation: Evaluation {
    struct Case: Sendable {
        let feedback: String
        let developerContext: [String: String]
        let clarificationTurns: [BetaFeedbackClarificationTurn]
        let screenshotName: String?
        let visualContext: String?
        let expectedBehavior: String

        var evaluationPrompt: String {
            var lines = ["User feedback: \(feedback)"]
            if !developerContext.isEmpty {
                let context = developerContext.sorted { $0.key < $1.key }
                    .map { "\($0.key): \($0.value)" }
                    .joined(separator: ", ")
                lines.append("Known context: \(context)")
            }
            if let visualContext {
                lines.append("Visible screenshot context: \(visualContext)")
            }
            for turn in clarificationTurns {
                lines.append("Previous question: \(turn.question)")
                lines.append("User answer: \(turn.response)")
            }
            return lines.joined(separator: "\n")
        }

        var analysisInput: FeedbackAnalysisInput {
            FeedbackAnalysisInput(
                originalFeedback: feedback,
                questionID: "clarification-evaluation",
                questionTitle: "What feedback do you have?",
                metadata: [:],
            developerContext: developerContext,
            clarificationTurns: clarificationTurns
        )
        }
    }

    static let cases: [Case] = [
        Case(
            feedback: "Continue didn't work.",
            developerContext: ["screen": "Checkout"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask neutrally what happened after Continue or what the user expected. Do not assume a payment attempt, error, crash, or navigation result."
        ),
        Case(
            feedback: "The wording feels robotic.",
            developerContext: [:],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask what wording or tone would feel more natural. Do not ask where the text appears or request a screenshot."
        ),
        Case(
            feedback: "This looks off.",
            developerContext: ["screen": "Profile", "area": "Avatar editor"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask what looks off or what the user expected to see without inventing a specific visual defect or interface element."
        ),
        Case(
            feedback: "After I tapped Continue on checkout, the app showed error 42 every time instead of opening confirmation.",
            developerContext: ["screen": "Checkout"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Return no question because the action, observed result, frequency, and expected result are already supplied."
        ),
        Case(
            feedback: "Continue didn't work.",
            developerContext: ["screen": "Checkout"],
            clarificationTurns: [
                BetaFeedbackClarificationTurn(
                    question: "What happened when you tapped Continue?",
                    response: "The button dimmed but I stayed on checkout."
                )
            ],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Do not repeat the previous question. Either ask one useful next question based on the new answer, such as what the user expected, or return no question."
        ),
        Case(
            feedback: "Everything feels slow.",
            developerContext: ["screen": "Search"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask when the slowness is noticeable or whether it affects Search more broadly. Do not assume a freeze, error, or particular control."
        ),
        Case(
            feedback: "The new home screen is much easier to use.",
            developerContext: ["screen": "Home"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Return no question because this positive feedback is already clear and does not need diagnosis."
        ),
        Case(
            feedback: "I don't understand what this screen is telling me.",
            developerContext: ["app": "WalkLock", "screen": "Home"],
            clarificationTurns: [],
            screenshotName: "walklock-home",
            visualContext: "WalkLock Home shows a large 2% daily progress ring, 88 / 4,000 steps, a daily-goal card, date controls, and tab navigation.",
            expectedBehavior: "Ask which information or progress relationship is unclear. It may refer to visible labels, but must not ask the user to describe the screenshot or assume which number is wrong."
        ),
        Case(
            feedback: "The percentages don't make sense to me.",
            developerContext: ["app": "WalkLock", "screen": "Unlock Ladder"],
            clarificationTurns: [],
            screenshotName: "walklock-ladder",
            visualContext: "An Unlock Ladder lists 10%, 20%, 30%, and later milestones; TikTok and LinkedIn appear at 10%, Instagram at 20%, with labels such as early unlock.",
            expectedBehavior: "Ask what the user expected the percentages to represent or which relationship is unclear. Do not claim the percentages are progress, time, or steps."
        ),
        Case(
            feedback: "I can't find where to change my goal.",
            developerContext: ["app": "WalkLock", "screen": "Settings"],
            clarificationTurns: [],
            screenshotName: "walklock-settings",
            visualContext: "WalkLock Settings shows categories including Goals & Locks, Automation & Reminders, More to Try, and App & Setup.",
            expectedBehavior: "Ask which kind of goal the user wants to change, or return no question if the screenshot makes the navigation need sufficiently actionable. Do not tell the user how to fix it."
        ),
        Case(
            feedback: "The assignment card looks broken.",
            developerContext: ["app": "ExamCram", "screen": "Today"],
            clarificationTurns: [],
            screenshotName: "examcram-today",
            visualContext: "The Upcoming Assignments card is visibly tilted inside a bright blue frame while surrounding course cards are level.",
            expectedBehavior: "Ask whether the visibly tilted assignment card is what looks broken or what appearance the user expected. Do not invent a loading or data failure."
        ),
        Case(
            feedback: "I can't answer this.",
            developerContext: ["app": "ExamCram", "screen": "Practice question"],
            clarificationTurns: [],
            screenshotName: "examcram-quiz",
            visualContext: "A multiple-choice question shows four answer options and a disabled Check button before any answer is selected.",
            expectedBehavior: "Ask whether the question is unclear or selecting an answer does not work. Do not assume the disabled Check button is the problem or that the user chose an answer."
        ),
        Case(
            feedback: "The answer editor is hard to use.",
            developerContext: ["app": "ExamCram", "screen": "Question editor"],
            clarificationTurns: [],
            screenshotName: "examcram-editor",
            visualContext: "A question editor shows a question field and stacked potential-answer cards, each with a Correct toggle, plus add and delete controls.",
            expectedBehavior: "Ask which part of editing answers feels difficult or what the user expected. Do not assume the Correct toggles, adding, deleting, scrolling, or text entry is the problem."
        ),
        Case(
            feedback: "I don't know what I'm supposed to do here.",
            developerContext: ["app": "Agent Alerts", "screen": "Onboarding"],
            clarificationTurns: [],
            screenshotName: "agentalerts-onboarding",
            visualContext: "The first of three onboarding pages explains Lock Screen agent updates and offers Skip, Read setup guide, and Continue actions.",
            expectedBehavior: "Ask whether the purpose of alerts or the next onboarding action is unclear. Do not assume Continue or the setup-guide link failed."
        ),
        Case(
            feedback: "I don't understand how to connect this.",
            developerContext: ["app": "Agent Alerts", "screen": "Pair a Computer"],
            clarificationTurns: [],
            screenshotName: "agentalerts-pairing",
            visualContext: "A pairing screen explains opening a setup webpage, completing verification, then scanning or pasting a one-time setup code; it offers Scan QR Code and Paste Setup Code.",
            expectedBehavior: "Ask whether the user is stuck creating the setup request or scanning or pasting it. Never ask them to share a key, code, or token."
        ),
        Case(
            feedback: "This setup explanation is confusing.",
            developerContext: ["app": "Agent Alerts", "screen": "Agent Alerts basics"],
            clarificationTurns: [],
            screenshotName: "agentalerts-webhook-basics",
            visualContext: "The final basics page diagrams Webhook HTTPS to iPhone Live Activity with a publish-only token and links to a setup guide.",
            expectedBehavior: "Ask which concept or step is unclear, such as connecting the agent or what the publish-only token does, without assuming prior technical knowledge."
        ),
        Case(
            feedback: "This screen feels overwhelming.",
            developerContext: ["app": "Agent Alerts", "screen": "Home"],
            clarificationTurns: [],
            screenshotName: "agentalerts-home",
            visualContext: "The Home screen combines a connect-first-agent prompt, recent alerts, a large Getting Started card, demo cards, filters, sorting, and tab navigation.",
            expectedBehavior: "Ask what the user came to do or which section feels overwhelming. Do not assume a particular card, control, or amount of text is the problem."
        ),
        Case(
            feedback: "The ring doesn't match my steps.",
            developerContext: ["app": "WalkLock", "screen": "Home"],
            clarificationTurns: [],
            screenshotName: "walklock-progress",
            visualContext: "WalkLock Home shows 78% in the ring and 3,158 / 4,000 steps in the daily-goal card.",
            expectedBehavior: "Ask what percentage or relationship the user expected, or whether rounding is the mismatch they noticed. Do not declare the calculation wrong."
        ),
        Case(
            feedback: "These alerts are hard to read.",
            developerContext: ["app": "Agent Alerts", "screen": "Notification Center"],
            clarificationTurns: [],
            screenshotName: "agentalerts-notification-center",
            visualContext: "Dark Notification Center cards contain a blue onboarding chart and two orange Codex progress cards with large status text, percentages, progress bars, and secondary labels.",
            expectedBehavior: "Ask which aspect is hardest to read, such as text, contrast, density, or hierarchy. Do not assume one card or a specific accessibility condition."
        )
    ]

    let questionShape = Metric("QuestionShape")
    let questionQuality = Metric("QuestionQuality")

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: Self.cases.map {
            ModelSample(prompt: $0.evaluationPrompt, expected: $0.expectedBehavior)
        })
    }

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        guard let expected = sample.expected,
              let evaluationCase = Self.cases.first(where: { $0.expectedBehavior == expected }) else {
            throw EvaluationError.unknownCase
        }
        let screenshot = try evaluationCase.screenshotName.map(Self.loadScreenshot(named:))
        guard let analysis = try await OnDeviceFeedbackAnalyzer().analyzeConversation(
            evaluationCase.analysisInput,
            screenshot: screenshot
        ) else {
            throw EvaluationError.modelUnavailable
        }
        return ModelSubject(value: analysis.nextQuestion?.text ?? "<no question>")
    }

    private static func loadScreenshot(named name: String) throws -> CGImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw EvaluationError.missingScreenshot(name)
        }
        return image
    }

    var evaluators: Evaluators {
        Evaluator { input, subject in
            let value = subject.value
            let previousQuestions = Self.cases
                .first(where: { $0.expectedBehavior == input.expected })?
                .clarificationTurns
                .map { $0.question.lowercased() } ?? []
            let bannedTerms = ["telemetry", "logs", "screenshot", "component", "diagnostics"]
            let isNoQuestion = value == "<no question>"
            let isSingleQuestion = value.filter { $0 == "?" }.count == 1
            let isGrounded = !bannedTerms.contains(where: value.lowercased().contains)
            let isNew = !previousQuestions.contains(value.lowercased())
            let expectation = input.expected ?? ""
            let requiresQuestion = expectation.hasPrefix("Ask ")
            let requiresNoQuestion = expectation.hasPrefix("Return no question")
            let meetsAskOrStopExpectation = requiresQuestion
                ? !isNoQuestion
                : (requiresNoQuestion ? isNoQuestion : true)
            let hasValidShape = isNoQuestion
                || (isSingleQuestion && value.count <= 240 && isGrounded && isNew)
            let passes = meetsAskOrStopExpectation && hasValidShape
            return passes ? questionShape.passing() : questionShape.failing()
        }
        ModelJudgeEvaluator(
            "QuestionQuality",
            scale: .numeric([
                4: "Ideal: useful, natural, grounded, non-assumptive, and correctly asks or stops.",
                3: "Good: useful and grounded with only a minor wording or focus issue.",
                2: "Weak: somewhat relevant but generic, repetitive, awkward, or mildly assumptive.",
                1: "Poor: nonsensical, technically framed, redundant, materially assumptive, or asks when it should stop."
            ]),
            judge: SystemLanguageModel.default,
            prompt: ModelJudgePrompt(
                instructions: """
                    You are a senior UX researcher evaluating one follow-up question generated
                    from everyday app feedback. Compare the response with the original feedback,
                    known context, conversation history, and expected behavior.

                    A strong response asks at most one natural question, follows the user's own
                    words, avoids unsupported assumptions, does not repeat an answered question,
                    and obtains a detail that would change diagnosis or a product decision. The
                    literal response <no question> is ideal when the report is already actionable
                    or no useful follow-up remains.

                    First identify what the user actually established. Then check the response for
                    invented details and repetition. Finally decide whether asking or stopping is
                    useful, and assign the matching score.
                    """,
                evaluationTarget: { $0 },
                reference: { sample, _ in
                    ["Expected behavior": sample.expected ?? ""]
                }
            )
        )
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: questionShape)
        aggregator.computeMean(of: questionQuality)
    }

    enum EvaluationError: Error {
        case unknownCase
        case modelUnavailable
        case missingScreenshot(String)
    }
}

private struct FeedbackClarificationEvaluationTests {
    @Test("Clarification questions are useful and non-assumptive")
    func clarificationQuestionQuality() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let evaluation = ClarificationQuestionEvaluation()
        let result = try await evaluation.run(info: [
            "dataset": "clarification-v1",
            "prompt": "curious-ux-designer-v1"
        ])
        let shape = result.aggregateValue(.mean(of: evaluation.questionShape))
        let quality = result.aggregateValue(.mean(of: evaluation.questionQuality))

        print("[BetaFeedbackKitEvals] questionShape=\(shape) questionQuality=\(quality)")

        #expect(shape == 1)
        #expect(quality >= 3)
    }
}
#endif
