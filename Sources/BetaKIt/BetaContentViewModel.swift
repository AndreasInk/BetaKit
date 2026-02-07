//
//  NotificationPermissionManager.swift
//  BetaKit
//
//  Created by Andreas Ink on 2/6/26.
//

import SwiftUI
@preconcurrency import UserNotifications
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Observable
public final class BetaContentViewModel {
    var showTestFlightFeedbackPrompt: Bool = false
    var showTestFlightScreenshotTip: Bool = false
    var showScreenshotOverlay: Bool = false
    var hasShownTestFlightFeedbackPrompt: Bool = false
    var testFlightFeedbackAnswer: String = ""
    var testFlightFeedbackQuestionId: String = ""
    public var feedbackQuestions: [TestFlightFeedbackQuestion]
    public var developerProfileImageURL: URL?
    public var allowsFeedbackPasteboardExport: Bool
    public var feedbackContextProvider: @Sendable () -> [String: String]
    
    var hasSeenTestFlightScreenshotTip: Bool {
        UserDefaults.standard.bool(forKey: "hasSeenTestFlightScreenshotTip")
    }
    
    func setHasSeenTestFlightScreenshotTip(_ hasSeen: Bool) {
        UserDefaults.standard.set(hasSeen, forKey: "hasSeenTestFlightScreenshotTip")
    }
    /// Check if the app is running in debug mode or TestFlight
    static func isDebugOrTestFlight() -> Bool {
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
        feedbackContextProvider: @escaping @Sendable () -> [String: String] = { [:] }
    ) {
        self.feedbackQuestions = feedbackQuestions
        self.developerProfileImageURL = developerProfileImageURL
        self.allowsFeedbackPasteboardExport = allowsFeedbackPasteboardExport
        self.feedbackContextProvider = feedbackContextProvider
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
            showTestFlightFeedbackPrompt = true
            return true
        case DeepLink.screenshotTipHost:
            showTestFlightScreenshotTip = true
            return true
        default:
            return false
        }
    }

    public func setup() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationCenter.default.post(name: Notification.Name("TestFlightScreenshotTaken"), object: nil)
            Self.scheduleTestFlightScreenshotTipNotificationInternal()
        }
        #endif
        if !hasSeenTestFlightScreenshotTip {
            showTestFlightScreenshotTip = true
        }
    }
    
    public func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

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

    private static func scheduleTestFlightScreenshotTipNotificationInternal() {
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

    private static func enqueueTestFlightScreenshotTip(center: UNUserNotificationCenter) {
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

    private static func screenshotTipBody() -> String {
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

        let metadata = [
            "question_id": questionId,
            "question_title": questionTitle,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "os": ProcessInfo.processInfo.operatingSystemVersionString
        ]
        let context = feedbackContextProvider()

        let output = Self.formatFeedbackPayload(
            answer: trimmedAnswer,
            metadata: metadata,
            context: context
        )

        #if os(iOS)
        UIPasteboard.general.string = output
        return true
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(output, forType: .string)
        #else
        return false
        #endif
    }

    private static func formatFeedbackPayload(
        answer: String,
        metadata: [String: String],
        context: [String: String]
    ) -> String {
        let sortedMetadata = metadata.sorted { $0.key < $1.key }
        let sortedContext = context.sorted { $0.key < $1.key }

        var lines: [String] = []
        lines.append("BetaKit Feedback")
        lines.append("")
        lines.append("Answer")
        lines.append(answer)
        lines.append("")
        lines.append("Metadata")
        lines.append(contentsOf: sortedMetadata.map { "\($0.key): \($0.value)" })

        if !sortedContext.isEmpty {
            lines.append("")
            lines.append("Context")
            lines.append(contentsOf: sortedContext.map { "\($0.key): \($0.value)" })
        }

        return lines.joined(separator: "\n")
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
        print("[BetaKit] \(event): \(info)")
        #endif
    }
}
