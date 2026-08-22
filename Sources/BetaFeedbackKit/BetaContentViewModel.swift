//
//  NotificationPermissionManager.swift
//  BetaFeedbackKit
//
//  Created by Andreas Ink on 2/6/26.
//

import SwiftUI
@preconcurrency import UserNotifications
import Darwin
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let betaFeedbackKitTestFlightScreenshotTaken = Notification.Name(
        "BetaFeedbackKitTestFlightScreenshotTaken"
    )
}

enum BetaFeedbackKitScreenshotEventKey {
    static let notificationConversationStarted = "notificationConversationStarted"
}

private final class BetaNotificationObserverToken: @unchecked Sendable {
    let token: NSObjectProtocol

    init(_ token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

@MainActor
@Observable
public final class BetaContentViewModel {
    enum PresentedSheet: String, Identifiable {
        case testFlightFeedbackPrompt
        case testFlightScreenshotTip

        var id: String { rawValue }
    }

    var presentedSheet: PresentedSheet?
    var showTestFlightFeedbackPrompt: Bool {
        get { presentedSheet == .testFlightFeedbackPrompt }
        set {
            if newValue {
                presentTestFlightFeedbackPrompt()
            } else if presentedSheet == .testFlightFeedbackPrompt {
                dismissPresentedSheet()
            }
        }
    }
    var showTestFlightScreenshotTip: Bool {
        get { presentedSheet == .testFlightScreenshotTip }
        set {
            if newValue {
                presentTestFlightScreenshotTip()
            } else if presentedSheet == .testFlightScreenshotTip {
                dismissPresentedSheet()
            }
        }
    }
    var showScreenshotOverlay: Bool = false
    var hasShownTestFlightFeedbackPrompt: Bool = false
    var testFlightFeedbackAnswer: String = ""
    var testFlightFeedbackQuestionId: String = ""
    public var feedbackQuestions: [TestFlightFeedbackQuestion]
    public var developerProfileImageURL: URL?
    public var allowsFeedbackPasteboardExport: Bool
    public var feedbackClarificationMode: BetaFeedbackClarificationMode
    public var feedbackNotificationMode: BetaFeedbackNotificationMode
    public var feedbackDiagnosticsMode: BetaFeedbackDiagnosticsMode {
        didSet {
            switch feedbackDiagnosticsMode {
            case .disabled:
                feedbackDiagnosticMonitor.stop()
            case .onDevice:
                startDiagnosticMonitoringIfNeeded()
            }
        }
    }
    public var feedbackContextProvider: @Sendable () -> [String: String]
    public internal(set) var latestFeedbackReport: BetaFeedbackReport?
    public private(set) var activeFeedbackStates: [BetaFeedbackState] = []
    @ObservationIgnored public var feedbackScreenshotProvider: BetaFeedbackScreenshotProvider?
    @ObservationIgnored public var onFeedbackPrepared: (@Sendable (BetaFeedbackReport) -> Void)?
    @ObservationIgnored var feedbackAnalyzer: any FeedbackAnalyzing = OnDeviceFeedbackAnalyzer()
    @ObservationIgnored var feedbackConversationAnalyzer: any FeedbackConversationAnalyzing = OnDeviceFeedbackAnalyzer()
    @ObservationIgnored var feedbackConversationStore: any BetaFeedbackConversationStoring = UserDefaultsFeedbackConversationStore()
    @ObservationIgnored var stateReporter: any BetaStateReporting = OnDeviceBetaStateReporter()
    @ObservationIgnored var feedbackDiagnosticMonitor: any FeedbackDiagnosticMonitoring = OnDeviceFeedbackDiagnosticMonitor()
    @ObservationIgnored private var betaStateRegistrations: [String: [BetaFeedbackStateRegistration]] = [:]
    @ObservationIgnored private var screenshotObserverToken: BetaNotificationObserverToken?
    #if os(iOS)
    @ObservationIgnored var activeConversationScreenshot: (id: UUID, image: CGImage)?
    #endif

    var hasSeenTestFlightScreenshotTip: Bool {
        UserDefaults.standard.bool(forKey: "hasSeenTestFlightScreenshotTip")
    }

    func setHasSeenTestFlightScreenshotTip(_ hasSeen: Bool) {
        UserDefaults.standard.set(hasSeen, forKey: "hasSeenTestFlightScreenshotTip")
    }
    /// Check if the app is running in debug mode or TestFlight
    nonisolated static func isDebugOrTestFlight() -> Bool {
        #if DEBUG
        return true
        #else
        // Check if running in TestFlight
        guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
        #endif
    }

    public init(
        feedbackQuestions: [TestFlightFeedbackQuestion] = TestFlightFeedbackQuestion.defaultQuestions,
        developerProfileImageURL: URL? = nil,
        allowsFeedbackPasteboardExport: Bool = false,
        feedbackContextProvider: @escaping @Sendable () -> [String: String] = { [:] },
        feedbackClarificationMode: BetaFeedbackClarificationMode = .disabled,
        feedbackDiagnosticsMode: BetaFeedbackDiagnosticsMode = .disabled,
        feedbackNotificationMode: BetaFeedbackNotificationMode = .disabled,
        feedbackScreenshotProvider: BetaFeedbackScreenshotProvider? = nil,
        onFeedbackPrepared: (@Sendable (BetaFeedbackReport) -> Void)? = nil
    ) {
        self.feedbackQuestions = feedbackQuestions
        self.developerProfileImageURL = developerProfileImageURL
        self.allowsFeedbackPasteboardExport = allowsFeedbackPasteboardExport
        self.feedbackClarificationMode = feedbackClarificationMode
        self.feedbackDiagnosticsMode = feedbackDiagnosticsMode
        self.feedbackNotificationMode = feedbackNotificationMode
        self.feedbackContextProvider = feedbackContextProvider
        self.feedbackScreenshotProvider = feedbackScreenshotProvider
        self.onFeedbackPrepared = onFeedbackPrepared
    }

    public enum DeepLink {
        public static let feedbackHost = "beta-feedback"
        public static let screenshotTipHost = "beta-screenshot-tip"
    }

    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let host = components.host else {
            return false
        }

        switch host {
        case DeepLink.feedbackHost:
            presentTestFlightFeedbackPrompt()
            return true
        case DeepLink.screenshotTipHost:
            presentTestFlightScreenshotTip()
            return true
        default:
            return false
        }
    }

    func presentTestFlightFeedbackPrompt() {
        showScreenshotOverlay = false
        presentedSheet = .testFlightFeedbackPrompt
    }

    func presentTestFlightScreenshotTip() {
        presentedSheet = .testFlightScreenshotTip
    }

    func dismissPresentedSheet() {
        presentedSheet = nil
    }

    public func setup() {
        startDiagnosticMonitoringIfNeeded()
        #if os(iOS)
        if screenshotObserverToken == nil {
            let token = NotificationCenter.default.addObserver(
                forName: UIApplication.userDidTakeScreenshotNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let notificationConversationStarted: Bool
                    if self.feedbackNotificationMode == .onScreenshot {
                        if #available(iOS 27.0, *) {
                            notificationConversationStarted = await self.startFeedbackNotificationConversation()
                        } else {
                            Self.scheduleTestFlightScreenshotTipNotificationInternal()
                            notificationConversationStarted = false
                        }
                    } else {
                        Self.scheduleTestFlightScreenshotTipNotificationInternal()
                        notificationConversationStarted = false
                    }
                    NotificationCenter.default.post(
                        name: .betaFeedbackKitTestFlightScreenshotTaken,
                        object: nil,
                        userInfo: [
                            BetaFeedbackKitScreenshotEventKey.notificationConversationStarted:
                                notificationConversationStarted
                        ]
                    )
                }
            }
            screenshotObserverToken = BetaNotificationObserverToken(token)
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.registerFeedbackNotificationCategories()
            await self.resumePendingFeedbackConversation()
        }
        #endif
        if !hasSeenTestFlightScreenshotTip {
            presentTestFlightScreenshotTip()
        }
    }

    @MainActor
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    @MainActor
    public func requestAuthorization(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }


    public func scheduleDailyTestFlightFeedbackReminder() {
        guard Self.isDebugOrTestFlight() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["testFlightFeedbackReminder"])

        let content = UNMutableNotificationContent()
        content.title = "Quick TestFlight question"
        content.body = "One sentence helps a ton. Tap to answer."
        content.sound = .default
        content.userInfo = ["source": "testFlightFeedbackReminder"]

        var dateComponents = DateComponents()
        dateComponents.hour = 20
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "testFlightFeedbackReminder",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    public func scheduleTestFlightScreenshotTipNotification() {
        Self.scheduleTestFlightScreenshotTipNotificationInternal()
    }

    nonisolated private static func scheduleTestFlightScreenshotTipNotificationInternal() {
        guard Self.isDebugOrTestFlight() else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            if status == .authorized || status == .provisional {
                Self.enqueueTestFlightScreenshotTip(center: center)
                return
            }
            if status == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    Self.enqueueTestFlightScreenshotTip(center: center)
                }
            }
        }
    }

    nonisolated private static func enqueueTestFlightScreenshotTip(center: UNUserNotificationCenter) {
        center.removePendingNotificationRequests(withIdentifiers: ["testFlightScreenshotTip"])

        let content = UNMutableNotificationContent()
        content.title = "Share beta feedback"
        content.body = screenshotTipBody()
        content.sound = .default
        content.userInfo = ["source": "testFlightScreenshotTip"]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(
            identifier: "testFlightScreenshotTip",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    nonisolated private static func screenshotTipBody() -> String {
        if #available(iOS 26.0, *) {
            return "Tap the check mark → Share Beta Feedback."
        }
        return "Tap Done → Share Beta Feedback."
    }

    @discardableResult
    public func copyFeedbackToPasteboard(answer: String, questionId: String, questionTitle: String) -> Bool {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard allowsFeedbackPasteboardExport, !trimmedAnswer.isEmpty else {
            return false
        }

        let input = makeFeedbackAnalysisInput(
            answer: trimmedAnswer,
            questionID: questionId,
            questionTitle: questionTitle
        )
        let report = Self.makeFeedbackReport(
            from: input,
            analysis: nil,
            clarificationResponse: nil
        )
        return copyFeedbackToPasteboard(report: report)
    }

    /// Copies a prepared report, including any clarification, when export is enabled.
    @discardableResult
    public func copyFeedbackToPasteboard(report: BetaFeedbackReport) -> Bool {
        guard allowsFeedbackPasteboardExport, !report.originalFeedback.isEmpty else {
            return false
        }

        #if os(iOS)
        UIPasteboard.general.string = report.formattedText
        return true
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(report.formattedText, forType: .string)
        #else
        return false
        #endif
    }

    func makeFeedbackAnalysisInput(
        answer: String,
        questionID: String,
        questionTitle: String
    ) -> FeedbackAnalysisInput {
        startDiagnosticMonitoringIfNeeded()
        let states = activeFeedbackStates.sorted { $0.domain < $1.domain }
        let feedbackDate = Date()
        return FeedbackAnalysisInput(
            originalFeedback: answer,
            questionID: questionID,
            questionTitle: questionTitle,
            metadata: Self.feedbackMetadata(
                questionID: questionID,
                questionTitle: questionTitle,
                date: feedbackDate
            ),
            developerContext: feedbackContextProvider(),
            activeStates: states,
            diagnosticContext: currentDiagnosticContext(
                matching: states,
                around: feedbackDate
            )
        )
    }

    @MainActor
    func analyzeFeedback(
        _ input: FeedbackAnalysisInput
    ) async throws -> BetaFeedbackClarificationAnalysis? {
        guard feedbackClarificationMode == .onDevice else { return nil }
        return try await feedbackAnalyzer.analyze(input)
    }

    @discardableResult
    func completeFeedback(
        _ input: FeedbackAnalysisInput,
        analysis: BetaFeedbackClarificationAnalysis?,
        clarificationResponse: String?
    ) -> BetaFeedbackReport {
        let report = Self.makeFeedbackReport(
            from: input,
            analysis: analysis,
            clarificationResponse: clarificationResponse
        )
        testFlightFeedbackAnswer = input.originalFeedback
        testFlightFeedbackQuestionId = input.questionID
        latestFeedbackReport = report
        hasShownTestFlightFeedbackPrompt = true
        onFeedbackPrepared?(report)
        return report
    }

    private static func makeFeedbackReport(
        from input: FeedbackAnalysisInput,
        analysis: BetaFeedbackClarificationAnalysis?,
        clarificationResponse: String?
    ) -> BetaFeedbackReport {
        let trimmedResponse = clarificationResponse?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return BetaFeedbackReport(
            originalFeedback: input.originalFeedback,
            questionID: input.questionID,
            questionTitle: input.questionTitle,
            analysis: analysis,
            clarificationResponse: trimmedResponse?.isEmpty == false ? trimmedResponse : nil,
            metadata: input.metadata,
            developerContext: input.developerContext,
            activeStates: input.activeStates,
            diagnosticContext: input.diagnosticContext
        )
    }

    /// Records a meaningful state for immediate feedback context and StateReporting correlation.
    @discardableResult
    public func reportBetaState(
        domain: String,
        state: String,
        metadata: [String: String] = [:]
    ) -> BetaFeedbackState? {
        applyBetaState(
            BetaFeedbackStateConfiguration(domain: domain, state: state, metadata: metadata)
        )
    }

    /// Clears the active state for a domain.
    public func clearBetaState(domain: String) {
        guard let domain = BetaStateValidation.normalizedDomain(domain) else { return }
        betaStateRegistrations.removeValue(forKey: domain)
        guard activeFeedbackStates.contains(where: { $0.domain == domain }) else { return }
        activeFeedbackStates.removeAll { $0.domain == domain }
        stateReporter.reportTransition(domain: domain, state: nil)
    }

    /// Rechecks the latest report for diagnostics delivered after submission.
    @discardableResult
    public func refreshLatestFeedbackDiagnostics() -> BetaFeedbackReport? {
        guard let report = latestFeedbackReport else { return nil }
        let refreshed = BetaFeedbackReport(
            originalFeedback: report.originalFeedback,
            questionID: report.questionID,
            questionTitle: report.questionTitle,
            analysis: report.analysis,
            clarificationResponse: report.clarificationResponse,
            clarificationTurns: report.clarificationTurns,
            metadata: report.metadata,
            developerContext: report.developerContext,
            activeStates: report.activeStates,
            diagnosticContext: currentDiagnosticContext(
                matching: report.activeStates,
                around: Self.feedbackDate(from: report.metadata)
            )
        )
        latestFeedbackReport = refreshed
        return refreshed
    }

    func activateBetaState(_ configuration: BetaFeedbackStateConfiguration, owner: UUID) {
        guard let configuration = normalizedBetaStateConfiguration(configuration) else { return }
        var registrations = betaStateRegistrations[configuration.domain, default: []]
        if let index = registrations.firstIndex(where: { $0.owner == owner }) {
            registrations[index] = .init(owner: owner, configuration: configuration)
        } else {
            registrations.append(.init(owner: owner, configuration: configuration))
        }
        betaStateRegistrations[configuration.domain] = registrations
        if let activeRegistration = registrations.last {
            _ = applyNormalizedBetaState(activeRegistration.configuration)
        }
    }

    func clearBetaState(domain: String, owner: UUID) {
        guard let domain = BetaStateValidation.normalizedDomain(domain),
              var registrations = betaStateRegistrations[domain],
              registrations.contains(where: { $0.owner == owner }) else { return }

        registrations.removeAll { $0.owner == owner }
        if let restored = registrations.last {
            betaStateRegistrations[domain] = registrations
            _ = applyNormalizedBetaState(restored.configuration)
        } else {
            betaStateRegistrations.removeValue(forKey: domain)
            guard activeFeedbackStates.contains(where: { $0.domain == domain }) else { return }
            activeFeedbackStates.removeAll { $0.domain == domain }
            stateReporter.reportTransition(domain: domain, state: nil)
        }
    }

    private func applyBetaState(
        _ configuration: BetaFeedbackStateConfiguration
    ) -> BetaFeedbackState? {
        guard let configuration = normalizedBetaStateConfiguration(configuration) else { return nil }
        betaStateRegistrations.removeValue(forKey: configuration.domain)
        return applyNormalizedBetaState(configuration)
    }

    private func normalizedBetaStateConfiguration(
        _ configuration: BetaFeedbackStateConfiguration
    ) -> BetaFeedbackStateConfiguration? {
        guard let domain = BetaStateValidation.normalizedDomain(configuration.domain),
              let state = BetaStateValidation.normalizedState(configuration.state) else { return nil }
        return BetaFeedbackStateConfiguration(
            domain: domain,
            state: state,
            metadata: BetaStateValidation.normalizedMetadata(configuration.metadata)
        )
    }

    private func applyNormalizedBetaState(
        _ configuration: BetaFeedbackStateConfiguration
    ) -> BetaFeedbackState {
        let domain = configuration.domain
        let state = configuration.state
        let metadata = configuration.metadata

        if let existing = activeFeedbackStates.first(where: { $0.domain == domain }),
           existing.state == state,
           existing.metadata == metadata {
            return existing
        }

        let snapshot = BetaFeedbackState(
            domain: domain,
            state: state,
            metadata: metadata
        )
        activeFeedbackStates.removeAll { $0.domain == domain }
        activeFeedbackStates.append(snapshot)
        activeFeedbackStates.sort { $0.domain < $1.domain }
        stateReporter.reportTransition(domain: domain, state: state)
        return snapshot
    }

    private func startDiagnosticMonitoringIfNeeded() {
        guard case .onDevice(let stateDomains) = feedbackDiagnosticsMode else { return }
        feedbackDiagnosticMonitor.start(stateDomains: stateDomains)
    }

    private func currentDiagnosticContext(
        matching states: [BetaFeedbackState],
        around feedbackDate: Date
    ) -> BetaFeedbackDiagnosticContext {
        guard case .onDevice = feedbackDiagnosticsMode else { return .disabled }
        return feedbackDiagnosticMonitor.context(matching: states, around: feedbackDate)
    }

    private static func feedbackMetadata(
        questionID: String,
        questionTitle: String,
        date: Date = Date()
    ) -> [String: String] {
        let info = Bundle.main.infoDictionary
        return [
            "app_version": info?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": info?["CFBundleVersion"] as? String ?? "unknown",
            "device": machineIdentifier(),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "question_id": questionID,
            "question_title": questionTitle,
            "timestamp": ISO8601DateFormatter().string(from: date)
        ]
    }

    private static func feedbackDate(from metadata: [String: String]) -> Date {
        guard let timestamp = metadata["timestamp"],
              let date = ISO8601DateFormatter().date(from: timestamp) else {
            return Date()
        }
        return date
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return "unknown" }
        let capacity = MemoryLayout.size(ofValue: systemInfo.machine)

        return withUnsafePointer(to: &systemInfo.machine) { pointer in
            pointer.withMemoryRebound(
                to: CChar.self,
                capacity: capacity
            ) { value in
                String(cString: value)
            }
        }
    }
}

public enum AnalyticsManager {
    public typealias EventHandler = @Sendable (_ event: String, _ info: [String: String]) -> Void

    private static let lock = NSLock()
    nonisolated(unsafe) private static var eventHandler: EventHandler = defaultEventHandler

    public static func configure(eventHandler: @escaping EventHandler) {
        lock.lock()
        self.eventHandler = eventHandler
        lock.unlock()
    }

    public static func reset() {
        configure(eventHandler: defaultEventHandler)
    }

    public static func logEvent(_ event: String, info: [String: String]) {
        lock.lock()
        let handler = eventHandler
        lock.unlock()
        handler(event, info)
    }

    private static func defaultEventHandler(_ event: String, _ info: [String: String]) {
        #if DEBUG
        print("[BetaFeedbackKit] \(event): \(info)")
        #endif
    }
}
