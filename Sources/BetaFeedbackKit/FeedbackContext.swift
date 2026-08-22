import Foundation
import SwiftUI

#if os(iOS) && canImport(StateReporting)
import StateReporting
#endif

#if os(iOS) && canImport(MetricKit)
import MetricKit
#endif

/// A meaningful, low-cardinality app state captured when feedback is prepared.
public struct BetaFeedbackState: Sendable, Equatable, Codable {
    public let domain: String
    public let state: String
    public let metadata: [String: String]
    public let updatedAt: Date

    public init(
        domain: String,
        state: String,
        metadata: [String: String] = [:],
        updatedAt: Date = .now
    ) {
        self.domain = domain
        self.state = state
        self.metadata = metadata
        self.updatedAt = updatedAt
    }
}

/// Controls whether BetaFeedbackKit listens for privacy-filtered MetricKit diagnostics.
public enum BetaFeedbackDiagnosticsMode: Sendable, Equatable {
    case disabled

    /// Listen on-device for diagnostics associated with the supplied BetaFeedbackKit state domains.
    case onDevice(stateDomains: Set<String>)
}

/// A system-observed diagnostic category safe to include in a feedback report.
public enum BetaFeedbackDiagnosticKind: String, Sendable, Equatable, Codable {
    case crash
    case hang
    case cpuException = "cpu_exception"
    case diskWriteException = "disk_write_exception"
    case appLaunch = "app_launch"
    case memoryException = "memory_exception"
    case other
}

/// An app state recorded by the system immediately before a diagnostic event.
public struct BetaFeedbackObservedState: Sendable, Equatable, Codable {
    public let domain: String
    public let state: String
    public let durationSeconds: Double

    public init(domain: String, state: String, durationSeconds: Double) {
        self.domain = domain
        self.state = state
        self.durationSeconds = durationSeconds
    }
}

/// A deliberately small, privacy-filtered measurement attached to diagnostic evidence.
public enum BetaFeedbackDiagnosticMeasurement: Sendable, Equatable, Codable {
    case durationSeconds(Double)
    case cpuSeconds(total: Double, sampled: Double)
    case bytesWritten(Double)
}

/// System-observed evidence that BetaFeedbackKit can safely associate with a report.
public struct BetaFeedbackDiagnosticEvidence: Sendable, Equatable, Codable {
    public let kind: BetaFeedbackDiagnosticKind
    public let timeRange: DateInterval
    public let observedStates: [BetaFeedbackObservedState]
    public let measurement: BetaFeedbackDiagnosticMeasurement?

    public init(
        kind: BetaFeedbackDiagnosticKind,
        timeRange: DateInterval,
        observedStates: [BetaFeedbackObservedState],
        measurement: BetaFeedbackDiagnosticMeasurement? = nil
    ) {
        self.kind = kind
        self.timeRange = timeRange
        self.observedStates = observedStates
        self.measurement = measurement
    }
}

/// Describes the diagnostic evidence available without implying that missing evidence disproves an issue.
public enum BetaFeedbackDiagnosticContext: Sendable, Equatable, Codable {
    case disabled
    case unavailable
    case notAvailableYet
    case evidence([BetaFeedbackDiagnosticEvidence])
}

protocol BetaStateReporting: Sendable {
    func reportTransition(domain: String, state: String?)
}

struct OnDeviceBetaStateReporter: BetaStateReporting {
    func reportTransition(domain: String, state: String?) {
        #if os(iOS) && canImport(StateReporting)
        if #available(iOS 27.0, *) {
            let reporter = StateReporter<Never, Never>.reporter(
                for: BetaStateValidation.systemDomain(for: domain)
            )
            reporter.reportTransition(to: state)
        }
        #endif
    }
}

protocol FeedbackDiagnosticMonitoring: Sendable {
    func start(stateDomains: Set<String>)
    func context(
        matching states: [BetaFeedbackState],
        around feedbackDate: Date
    ) -> BetaFeedbackDiagnosticContext
    func stop()
}

#if os(iOS) && canImport(MetricKit)
@available(iOS 27.0, *)
private final class MetricKitObservation: @unchecked Sendable {
    let manager: MetricManager
    var task: Task<Void, Never>?

    init(manager: MetricManager) {
        self.manager = manager
    }

    deinit {
        task?.cancel()
    }
}
#endif

final class OnDeviceFeedbackDiagnosticMonitor: FeedbackDiagnosticMonitoring, @unchecked Sendable {
    private let lock = NSLock()
    private var configuredDomains: Set<String> = []
    private var evidence: [BetaFeedbackDiagnosticEvidence] = []

    #if os(iOS) && canImport(MetricKit)
    private var observation: AnyObject?
    #endif

    func start(stateDomains: Set<String>) {
        let logicalDomains = Set(stateDomains.compactMap(BetaStateValidation.normalizedDomain))
        guard !logicalDomains.isEmpty else {
            stop()
            return
        }

        #if os(iOS) && canImport(MetricKit)
        if #available(iOS 27.0, *) {
            startAvailable(stateDomains: logicalDomains)
        } else {
            lock.lock()
            configuredDomains = logicalDomains
            lock.unlock()
        }
        #else
        lock.lock()
        configuredDomains = logicalDomains
        lock.unlock()
        #endif
    }

    func context(
        matching states: [BetaFeedbackState],
        around feedbackDate: Date
    ) -> BetaFeedbackDiagnosticContext {
        #if os(iOS) && canImport(MetricKit)
        if #available(iOS 27.0, *) {
            return availableContext(matching: states, around: feedbackDate)
        }
        return .unavailable
        #else
        return .unavailable
        #endif
    }

    func stop() {
        #if os(iOS) && canImport(MetricKit)
        if #available(iOS 27.0, *) {
            stopAvailable()
        }
        #endif
    }

    deinit {
        #if os(iOS) && canImport(MetricKit)
        if #available(iOS 27.0, *) {
            (observation as? MetricKitObservation)?.task?.cancel()
        }
        #endif
    }

    private func record(_ item: BetaFeedbackDiagnosticEvidence) {
        lock.lock()
        defer { lock.unlock() }
        guard !evidence.contains(item) else { return }
        evidence.append(item)
        evidence = Array(evidence.suffix(50))
    }
}

private struct StatePair: Hashable {
    let domain: String
    let state: String
}

enum BetaDiagnosticCorrelation {
    static func relatedEvidence(
        _ evidence: [BetaFeedbackDiagnosticEvidence],
        states: [BetaFeedbackState],
        feedbackDate: Date
    ) -> [BetaFeedbackDiagnosticEvidence] {
        let windowStart = feedbackDate.addingTimeInterval(-30 * 60)
        return evidence.filter { item in
            guard item.timeRange.end >= windowStart,
                  item.timeRange.start <= feedbackDate else {
                return false
            }

            return item.observedStates.contains { observed in
                states.contains { state in
                    state.domain == observed.domain
                        && state.state == observed.state
                        && item.timeRange.end >= state.updatedAt
                }
            }
        }
    }
}

#if os(iOS) && canImport(MetricKit)
@available(iOS 27.0, *)
private extension OnDeviceFeedbackDiagnosticMonitor {
    func startAvailable(stateDomains logicalDomains: Set<String>) {
        lock.lock()
        if configuredDomains == logicalDomains,
           (observation as? MetricKitObservation)?.task != nil {
            lock.unlock()
            return
        }
        let oldObservation = observation as? MetricKitObservation
        let domainMap = Dictionary(uniqueKeysWithValues: logicalDomains.map {
            (BetaStateValidation.systemDomain(for: $0), $0)
        })
        let manager = MetricManager(
            enabledStateReportingDomains: Set(domainMap.keys.map(StateReportingDomain.init(rawValue:)))
        )
        let newObservation = MetricKitObservation(manager: manager)
        configuredDomains = logicalDomains
        evidence = []
        observation = newObservation
        lock.unlock()

        oldObservation?.task?.cancel()
        let task = Task { [weak self, manager] in
            for await report in manager.diagnosticReports {
                guard !Task.isCancelled else { return }
                guard let mapped = Self.map(report, domainMap: domainMap) else { continue }
                self?.record(mapped)
            }
        }

        lock.lock()
        if configuredDomains == logicalDomains, observation === newObservation {
            newObservation.task = task
        } else {
            task.cancel()
        }
        lock.unlock()
    }

    func availableContext(
        matching states: [BetaFeedbackState],
        around feedbackDate: Date
    ) -> BetaFeedbackDiagnosticContext {
        lock.lock()
        let hasConfiguredDomains = !configuredDomains.isEmpty
        let availableEvidence = evidence
        let isListening = (observation as? MetricKitObservation)?.task != nil
        lock.unlock()

        guard hasConfiguredDomains, isListening else { return .unavailable }
        let matches = BetaDiagnosticCorrelation.relatedEvidence(
            availableEvidence,
            states: states,
            feedbackDate: feedbackDate
        )
        return matches.isEmpty ? .notAvailableYet : .evidence(matches)
    }

    func stopAvailable() {
        lock.lock()
        let oldObservation = observation as? MetricKitObservation
        observation = nil
        configuredDomains = []
        evidence = []
        lock.unlock()
        oldObservation?.task?.cancel()
    }

    static func map(
        _ report: DiagnosticReport,
        domainMap: [String: String]
    ) -> BetaFeedbackDiagnosticEvidence? {
        let observedStates = report.environment.states.compactMap { state -> BetaFeedbackObservedState? in
            guard let logicalDomain = domainMap[state.domain] else { return nil }
            return BetaFeedbackObservedState(
                domain: logicalDomain,
                state: state.label,
                durationSeconds: state.duration.converted(to: .seconds).value
            )
        }
        guard !observedStates.isEmpty else { return nil }

        let kind: BetaFeedbackDiagnosticKind
        let measurement: BetaFeedbackDiagnosticMeasurement?
        switch report.result {
        case .crash:
            kind = .crash
            measurement = nil
        case .hang(let diagnostic):
            kind = .hang
            measurement = .durationSeconds(diagnostic.hangDuration.converted(to: .seconds).value)
        case .cpuException(let diagnostic):
            kind = .cpuException
            measurement = .cpuSeconds(
                total: diagnostic.totalCPUTime.converted(to: .seconds).value,
                sampled: diagnostic.totalSampledTime.converted(to: .seconds).value
            )
        case .diskWriteException(let diagnostic):
            kind = .diskWriteException
            measurement = .bytesWritten(diagnostic.totalBytesWritten.converted(to: .bytes).value)
        case .appLaunch(let diagnostic):
            kind = .appLaunch
            measurement = .durationSeconds(diagnostic.launchDuration.converted(to: .seconds).value)
        case .memoryException:
            kind = .memoryException
            measurement = nil
        @unknown default:
            return nil
        }

        return BetaFeedbackDiagnosticEvidence(
            kind: kind,
            timeRange: report.timeRange,
            observedStates: observedStates.sorted {
                ($0.domain, $0.state) < ($1.domain, $1.state)
            },
            measurement: measurement
        )
    }
}
#endif

enum BetaStateValidation {
    static func normalizedDomain(_ value: String) -> String? {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard candidate.unicodeScalars.allSatisfy(allowed.contains),
              candidate.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return candidate
    }

    static func normalizedState(_ value: String) -> String? {
        let candidate = value
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.count <= 128 else { return nil }
        return candidate
    }

    static func normalizedMetadata(_ values: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: values
            .sorted { $0.key < $1.key }
            .prefix(20)
            .compactMap { key, value -> (String, String)? in
                let cleanKey = String(key.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                guard !cleanKey.isEmpty else { return nil }
                let cleanValue = String(value
                    .split(whereSeparator: \Character.isWhitespace)
                    .joined(separator: " ")
                    .prefix(500))
                return (cleanKey, cleanValue)
            })
    }

    static func systemDomain(for logicalDomain: String) -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.andreasink.BetaFeedbackKit"
        return "\(bundleID).betafeedbackkit.\(logicalDomain)"
    }
}

private struct BetaFeedbackStateModifier: ViewModifier {
    let domain: String
    let state: String
    let metadata: [String: String]
    let viewModel: BetaContentViewModel
    @State private var registrationID = UUID()

    private var configuration: BetaFeedbackStateConfiguration {
        BetaFeedbackStateConfiguration(domain: domain, state: state, metadata: metadata)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                viewModel.activateBetaState(configuration, owner: registrationID)
            }
            .onChange(of: configuration) { oldValue, newValue in
                if oldValue.domain != newValue.domain {
                    viewModel.clearBetaState(domain: oldValue.domain, owner: registrationID)
                }
                viewModel.activateBetaState(newValue, owner: registrationID)
            }
            .onDisappear {
                viewModel.clearBetaState(domain: domain, owner: registrationID)
            }
    }
}

struct BetaFeedbackStateConfiguration: Sendable, Equatable {
    let domain: String
    let state: String
    let metadata: [String: String]
}

struct BetaFeedbackStateRegistration: Sendable, Equatable {
    let owner: UUID
    let configuration: BetaFeedbackStateConfiguration
}

public extension View {
    /// Captures a meaningful state locally and mirrors it to StateReporting on iOS 27.
    func betaState(
        domain: String,
        state: String,
        metadata: [String: String] = [:],
        viewModel: BetaContentViewModel
    ) -> some View {
        modifier(
            BetaFeedbackStateModifier(
                domain: domain,
                state: state,
                metadata: metadata,
                viewModel: viewModel
            )
        )
    }
}
