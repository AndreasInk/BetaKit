#if canImport(Evaluations) && canImport(FoundationModels)
import Evaluations
import Foundation
import FoundationModels
import ImageIO
import Testing
@testable import BetaFeedbackKit

private actor FoundationModelEvaluationLock {
    static let shared = FoundationModelEvaluationLock()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isLocked else {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

private func hasClarificationOutput(_ output: String) -> Bool {
    let value = output.trimmingCharacters(in: .whitespacesAndNewlines)
    return !value.isEmpty && value != "<no question>" && value.count <= 240
}

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
            expectedBehavior: "Ask what happened after pressing \"Continue\" or what the user expected. Do not assume an outcome."
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
            feedback: "The new card isn't as glassy as it was.",
            developerContext: ["screen": "Home", "feature": "home_experiment"],
            clarificationTurns: [
                BetaFeedbackClarificationTurn(
                    question: "How would you describe the exact look you noticed—or any changes you'd like to see?",
                    response: "The card is more flat, it should use Liquid Glass so it reflects the blue above it."
                )
            ],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful remaining question, such as where the flatter appearance is most noticeable. Do not repeat the answered request for Liquid Glass or ask for another description of the desired style."
        ),
        Case(
            feedback: "Bad ui",
            developerContext: [
                "feature": "settings_information_architecture",
                "screen": "settings",
                "screen_summary": "Settings and controls"
            ],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask which visual area or layout change would improve the settings screen without inventing a specific defect."
        ),
        Case(
            feedback: "Bad ui",
            developerContext: [
                "feature": "settings_information_architecture",
                "screen": "settings",
                "screen_summary": "Settings and controls"
            ],
            clarificationTurns: [
                BetaFeedbackClarificationTurn(
                    question: "What specific visual element or layout change would make the interface clearer to you?",
                    response: "More padding"
                )
            ],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask where the additional padding should apply. Do not ask again what visual element or layout change the user wants."
        ),
        Case(
            feedback: "Bad ui",
            developerContext: [
                "feature": "settings_information_architecture",
                "screen": "settings",
                "screen_summary": "Settings and controls"
            ],
            clarificationTurns: [
                BetaFeedbackClarificationTurn(
                    question: "What specific visual element or layout change would make the interface clearer to you?",
                    response: "More padding"
                ),
                BetaFeedbackClarificationTurn(
                    question: "Where should the extra padding be applied?",
                    response: "Full view"
                )
            ],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful remaining question without repeating the already supplied padding request or its full-view scope."
        ),
        Case(
            feedback: "After I tapped Continue on checkout, the app showed error 42 every time instead of opening confirmation.",
            developerContext: ["screen": "Checkout"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful remaining question, such as whether error 42 appears immediately or after a delay. Do not repeat the action, result, frequency, or expected result already supplied."
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
            expectedBehavior: "Ask one useful next question based on the new answer, such as what the user expected. Do not repeat the previous question."
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
            expectedBehavior: "Ask what specifically made the home screen easier to use so the positive feedback becomes more actionable."
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
            expectedBehavior: "Ask which kind of goal the user wants to change. Do not tell the user how to fix it."
        ),
        Case(
            feedback: "Other settings screens would have a sub section here rather than all the elements on one screen",
            developerContext: [
                "app": "WalkLock",
                "screen": "Settings",
                "screen_summary": "settings and controls"
            ],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask which settings should be grouped together or what subsection the user expected. Do not ask about wording, tone, or copy."
        ),
        Case(
            feedback: "This settings page is confusing rather than simple.",
            developerContext: ["app": "WalkLock", "screen": "Settings"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask which part of the settings page feels confusing because this comparison does not propose a concrete structural change."
        ),
        Case(
            feedback: "Don't move the buttons; the page is confusing.",
            developerContext: ["app": "WalkLock", "screen": "Settings"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask what else about the page is confusing. Respect the instruction not to move the buttons."
        ),
        Case(
            feedback: "Move goal controls into Goals & Locks so I can find them from Settings.",
            developerContext: ["app": "WalkLock", "screen": "Settings"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful detail about the proposed grouping, such as whether all goal controls should move there. Do not ask the user to restate the requested destination."
        ),
        Case(
            feedback: "Make the progress ring blue like the goal card instead of gray.",
            developerContext: ["app": "WalkLock", "screen": "Home"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful detail about the desired blue treatment, such as whether it should match the goal card in every state. Do not ask the user to restate the requested color change."
        ),
        Case(
            feedback: "Rename Automation & Reminders to Reminders; automation sounds too technical.",
            developerContext: ["app": "WalkLock", "screen": "Settings"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful detail about the rename, such as whether other automation wording also feels too technical. Do not ask the user to repeat the replacement label or reason."
        ),
        Case(
            feedback: "Increase the contrast of the secondary labels on the dark card so I can read them.",
            developerContext: ["app": "Agent Alerts", "screen": "Notification Center"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask one useful detail about readability, such as whether the issue occurs for every secondary label. Do not ask the user to restate the requested contrast change."
        ),
        Case(
            feedback: "This section is hard to use.",
            developerContext: ["app": "WalkLock", "screen": "Settings"],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask what part of the section feels hard to use without inventing a control or interaction."
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
            expectedBehavior: "Ask which part of connecting is unclear. Never ask them to share a key, code, or token."
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
            feedback: "The unlock timing feels wrong.",
            developerContext: [
                "app": "WalkLock",
                "screen": "Home",
                "domain_context": "WalkLock unlocks selected apps when the user reaches configured daily step milestones; this feedback is about milestone-based unlocking, not clock time."
            ],
            clarificationTurns: [],
            screenshotName: nil,
            visualContext: nil,
            expectedBehavior: "Ask which step milestone unlocked earlier or later than expected, or what milestone behavior the user expected. Use the supplied domain meaning; do not interpret timing as time of day, invent an app, or claim the unlock rule is wrong."
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

    static var evaluatedCases: [Case] {
        if let requestedIndex = ProcessInfo.processInfo.environment["BETA_FEEDBACK_EVAL_CASE_INDEX"]
            .flatMap(Int.init),
           cases.indices.contains(requestedIndex) {
            return [cases[requestedIndex]]
        }
        // Production invokes the model only before the single allowed follow-up.
        let productionCases = cases.filter(\.clarificationTurns.isEmpty)
        if ProcessInfo.processInfo.environment["BETA_FEEDBACK_EVAL_SCREENSHOTS_ONLY"] == "1" {
            return productionCases.filter { $0.screenshotName != nil }
        }
        guard let shard = ProcessInfo.processInfo.environment["BETA_FEEDBACK_EVAL_SHARD"]?
            .split(separator: "/")
            .compactMap({ Int($0) }),
            shard.count == 2,
            shard[0] >= 1,
            shard[1] >= shard[0] else {
            return productionCases
        }
        let index = shard[0] - 1
        let count = shard[1]
        return productionCases.enumerated().compactMap { offset, value in
            offset % count == index ? value : nil
        }
    }

    let clarificationPresence = Metric("ClarificationPresence")
    let questionQuality = Metric("QuestionQuality")

    var dataset: ArrayLoader<ModelSample<String>> {
        ArrayLoader(samples: Self.evaluatedCases.map {
            ModelSample(prompt: $0.evaluationPrompt, expected: $0.expectedBehavior)
        })
    }

    func subject(from sample: ModelSample<String>) async throws -> ModelSubject<String> {
        guard let expected = sample.expected,
              let evaluationCase = Self.cases.first(where: { $0.expectedBehavior == expected }) else {
            throw EvaluationError.unknownCase
        }
        await FoundationModelEvaluationLock.shared.acquire()
        do {
            let screenshot = try evaluationCase.screenshotName.map(Self.loadScreenshot(named:))
            guard let analysis = try await OnDeviceFeedbackAnalyzer().analyzeConversation(
                evaluationCase.analysisInput,
                screenshot: screenshot
            ) else {
                throw EvaluationError.modelUnavailable
            }
            await FoundationModelEvaluationLock.shared.release()
            let question = analysis.nextQuestion?.text ?? "<no question>"
            return ModelSubject(value: question)
        } catch {
            await FoundationModelEvaluationLock.shared.release()
            throw error
        }
    }

    private static func loadScreenshot(named name: String) throws -> CGImage {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw EvaluationError.missingScreenshot(name)
        }
        guard let maximumDimension = ProcessInfo.processInfo.environment[
            "BETA_FEEDBACK_EVAL_IMAGE_MAX_DIMENSION"
        ].flatMap(Int.init), maximumDimension > 0 else {
            print("[BetaFeedbackKitEvals][image] name=\(name) dimensions=\(image.width)x\(image.height) mode=original")
            return image
        }
        let resized = FeedbackScreenshotPreprocessor.resizedForModel(
            image,
            maximumDimension: maximumDimension
        )
        print("[BetaFeedbackKitEvals][image] name=\(name) dimensions=\(resized.width)x\(resized.height) mode=max-\(maximumDimension)")
        return resized
    }

    var evaluators: Evaluators {
        Evaluator { input, subject in
            let question = subject.value
            let hasClarification = hasClarificationOutput(question)
            if !hasClarification {
                let feedback = Self.cases.first {
                    $0.expectedBehavior == input.expected
                }?.feedback ?? "unknown"
                print(
                    "[BetaFeedbackKitEvals][failure] feedback=\(feedback) "
                        + "expectedClarification=true output=\(question)"
                )
            }
            return hasClarification
                ? clarificationPresence.passing()
                : clarificationPresence.failing()
        }
        ModelJudgeEvaluator(
            "QuestionQuality",
            scale: .numeric([
                4: "Ideal: relevant, useful, grounded in the supplied feedback and context, natural for a tester, and safe.",
                3: "Good: relevant and grounded, with only a minor wording or usefulness issue.",
                2: "Weak: related to the feedback but generic, redundant, awkward, or mildly assumptive.",
                1: "Poor: irrelevant, unsafe, materially assumptive, repeats answered information, or would not help the developer."
            ]),
            judge: SystemLanguageModel.default,
            prompt: ModelJudgePrompt(
                instructions: """
                    Evaluate the quality of one follow-up question for everyday app feedback.
                    Judge whether it would obtain a useful missing detail, stays grounded in what
                    the tester and supplied context establish, avoids invented facts or causes,
                    and uses clear neutral language.

                    Focus on whether the output makes one clear, low-effort follow-up request.
                    Punctuation is not a quality signal. Use the expected behavior as guidance,
                    not as required wording. Assign the score that best matches the rubric.
                    """,
                evaluationTarget: { $0 },
                reference: { sample, _ in
                    [
                        "Original feedback and context": sample.input.promptDescription,
                        "Expected behavior": sample.expected ?? ""
                    ]
                }
            )
        )
    }

    func aggregateMetrics(using aggregator: inout MetricsAggregator) {
        aggregator.computeMean(of: clarificationPresence)
        aggregator.computeMean(of: questionQuality)
        aggregator.computeMinimum(of: questionQuality)
    }

    enum EvaluationError: Error {
        case unknownCase
        case modelUnavailable
        case missingScreenshot(String)
    }
}

private struct FeedbackClarificationEvaluationTests {
    @Test("Clarification presence does not grade punctuation")
    func clarificationPresenceContract() {
        #expect(hasClarificationOutput("What happened?"))
        #expect(hasClarificationOutput("Please describe what happened."))
        #expect(!hasClarificationOutput("<no question>"))
    }

    @Test("Clarification output has one useful, grounded question")
    func clarificationQuestionQuality() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { return }
        let evaluation = ClarificationQuestionEvaluation()
        let result = try await evaluation.run(info: [
            "dataset": "single-followup-quality-v9",
            "prompt": "simple-feedback-quality-v9"
        ])
        let presence = result.aggregateValue(.mean(of: evaluation.clarificationPresence))
        let quality = result.aggregateValue(.mean(of: evaluation.questionQuality))
        let minimumQuality = result.aggregateValue(.minimum(of: evaluation.questionQuality))
        print(
            "[BetaFeedbackKitEvals] clarificationPresence=\(presence) "
                + "questionQuality=\(quality) minimumQuestionQuality=\(minimumQuality)"
        )

        #expect(presence == 1)
        #expect(quality >= 3)
        #expect(minimumQuality >= 2)
    }
}
#endif
