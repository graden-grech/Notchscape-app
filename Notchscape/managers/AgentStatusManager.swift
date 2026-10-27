import Combine
import Foundation
import Network
import Defaults

enum AgentActivityState: String, Codable {
    case working
    case needsInput
    case completed
    case interrupted
    case usageLimited

    var label: String {
        switch self {
        case .working: "Working"
        case .needsInput: "Needs input"
        case .completed: "Completed"
        case .interrupted: "Interrupted"
        case .usageLimited: "Usage limit reached"
        }
    }

    var symbol: String {
        switch self {
        case .working: "sparkles"
        case .needsInput: "person.crop.circle.badge.questionmark"
        case .completed: "checkmark.circle.fill"
        case .interrupted: "pause.circle.fill"
        case .usageLimited: "exclamationmark.circle.fill"
        }
    }
}

struct AgentActivity: Identifiable, Codable, Equatable {
    let id: String
    var provider: String
    var title: String
    var detail: String
    var state: AgentActivityState
    var startedAt: Date = Date()
    var updatedAt: Date
}

@MainActor
final class AgentStatusManager: ObservableObject {
    static let shared = AgentStatusManager()
    static let port: UInt16 = 43_765

    @Published private(set) var activities: [AgentActivity] = []
    @Published private(set) var isListening = false
    @Published private(set) var lastError: String?
    @Published private(set) var history: [AgentHistoryEntry] = []

    private var listener: NWListener?
    private var dismissalTasks: [String: Task<Void, Never>] = [:]
    private var lastWorkingPublishAt: [String: Date] = [:]
    private var limitedSessions: [String: Date] = [:]
    private var interruptedSessions: [String: Date] = [:]
    private let chatTitles = AgentChatTitleResolver()
    private struct HistoryRun {
        let id: UUID
        let startedAt: Date
        var finished = false
    }
    private var historyRuns: [String: HistoryRun] = [:]

    private init() {
        history = Array(Defaults[.agentHistory].prefix(50))
        start()
    }

    func clearHistory() {
        history = []
        Defaults[.agentHistory] = []
        historyRuns = [:]
    }

    private func recordOutcome(activityID: String, provider: String, title: String, event: String, state: AgentActivityState, now: Date) {
        guard Defaults[.agentHistoryEnabled] else { return }
        if event == "UserPromptSubmit" || historyRuns[activityID] == nil
            || (state == .working && historyRuns[activityID]?.finished == true) {
            historyRuns[activityID] = HistoryRun(id: UUID(), startedAt: now)
        }
        if historyRuns.count > 64,
           let oldest = historyRuns.min(by: { $0.value.startedAt < $1.value.startedAt })?.key {
            historyRuns[oldest] = nil
        }
        guard state == .completed || state == .interrupted || state == .usageLimited,
              var run = historyRuns[activityID] else { return }
        // Stop + SessionEnd for the same turn update one row, not two.
        history.removeAll { $0.id == run.id }
        history.insert(AgentHistoryEntry(id: run.id, provider: provider, title: title,
            state: state, startedAt: run.startedAt, endedAt: now), at: 0)
        history = Array(history.prefix(50))
        Defaults[.agentHistory] = history
        run.finished = true
        historyRuns[activityID] = run
    }

    func start() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            // requiredLocalEndpoint already specifies the port. Passing it
            // again through `on:` is rejected with EINVAL by Network.framework.
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.receive(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isListening = true
                        self.lastError = nil
                    case .failed(let error):
                        self.isListening = false
                        self.lastError = error.localizedDescription
                        self.listener = nil
                    case .cancelled:
                        self.isListening = false
                        self.listener = nil
                    default:
                        break
                    }
                }
            }
            self.listener = listener
            listener.start(queue: .global(qos: .utility))
        } catch {
            lastError = error.localizedDescription
        }
    }

    private nonisolated func receive(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5) { connection.cancel() }
        collect(on: connection, data: Data())
    }

    private nonisolated func collect(on connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, complete, error in
            var accumulated = data
            if let chunk { accumulated.append(chunk) }
            guard accumulated.count <= 256 * 1024 else { connection.cancel(); return }

            if complete || error != nil || accumulated.containsHTTPBody {
                let body = accumulated.httpBody
                if !body.isEmpty {
                    let provider = accumulated.httpRequestPath.contains("claude")
                        ? "Claude Code"
                        : "Codex"
                    Task { @MainActor in self?.ingest(body, provider: provider) }
                }
                let response = "HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            self?.collect(on: connection, data: accumulated)
        }
    }

    private func ingest(_ data: Data, provider: String) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = object["hook_event_name"] as? String
        else { return }

        let resolvedProvider = (object["provider"] as? String) ?? provider
        AgentInsightsManager.shared.ingest(object, provider: resolvedProvider)
        if event == "UsageUpdate" { return } // A reading is not a task-state event.

        let sessionID = (object["session_id"] as? String) ?? UUID().uuidString
        let cwd = object["cwd"] as? String
        let tool = object["tool_name"] as? String
        let activityID = "\(resolvedProvider):\(sessionID)"
        let explicitTitle = AgentChatTitlePolicy.explicit(in: object)
        let title = explicitTitle
            ?? activities.first(where: { $0.id == activityID })?.title
            ?? AgentChatTitlePolicy.fallback(provider: resolvedProvider, cwd: cwd)
        let now = Date()
        limitedSessions = limitedSessions.filter { now.timeIntervalSince($0.value) < 3600 }
        interruptedSessions = interruptedSessions.filter { now.timeIntervalSince($0.value) < 3600 }
        // A new user turn is the only event that clears a previous quota failure.
        // A trailing Stop hook often arrives without the original error payload.
        if event == "UserPromptSubmit" || event == "SessionStart" {
            limitedSessions[activityID] = nil
            interruptedSessions[activityID] = nil
        }
        // A trailing SessionEnd is not evidence of success after an explicit
        // interrupt. Keep the interrupted outcome until a new user turn starts.
        if (event == "Stop" || event == "SessionEnd") && interruptedSessions[activityID] != nil { return }

        let searchablePayload = Self.flattenedStrings(in: object).joined(separator: " ").lowercased()
        let hitUsageLimit = Self.indicatesUsageLimitReached(
            event: event,
            payload: searchablePayload
        )

        let state: AgentActivityState
        if hitUsageLimit {
            state = .usageLimited
            limitedSessions[activityID] = now
        } else {
            guard limitedSessions[activityID] == nil else { return }
            switch event {
            case "PermissionRequest": state = .needsInput
            case "Stop", "SessionEnd": state = .completed
            case "Interrupt": state = .interrupted
            default: state = .working
            }
        }

        let detail: String
        if state == .interrupted { interruptedSessions[activityID] = now }
        switch state {
        case .usageLimited: detail = "Usage limit reached"
        default: switch event {
        case "PermissionRequest": detail = "Waiting for approval"
        case "Stop": detail = "Turn finished"
        case "SessionEnd": detail = "Session finished"
        case "Interrupt": detail = "Turn interrupted"
        case "PreToolUse": detail = tool.map { "Using \($0)" } ?? "Using a tool"
        case "PostToolUse": detail = tool.map { "Finished \($0)" } ?? "Tool finished"
        case "SubagentStart": detail = "Subagent started"
        case "SubagentStop": detail = "Subagent finished"
        case "UserPromptSubmit": detail = "Thinking"
        default: detail = "Active"
        }
        }

        // Codex can emit PreToolUse/PostToolUse hooks in rapid bursts. Updating
        // SwiftUI for every hook needlessly re-renders the notch and can compete
        // with coding apps and DisplayLink-driven screens.
        recordOutcome(activityID: activityID, provider: resolvedProvider, title: title, event: event, state: state, now: now)
        if state == .working,
           let lastPublish = lastWorkingPublishAt[activityID],
           now.timeIntervalSince(lastPublish) < AppPerformanceManager.shared.hookInterval,
           explicitTitle == nil || explicitTitle == activities.first(where: { $0.id == activityID })?.title {
            return
        }

        if state == .working {
            lastWorkingPublishAt[activityID] = now
        } else {
            lastWorkingPublishAt[activityID] = nil
        }

        let activity = AgentActivity(
            id: activityID,
            provider: resolvedProvider,
            title: title,
            detail: detail,
            state: state,
            startedAt: activities.first(where: { $0.id == activityID })?.startedAt ?? now,
            updatedAt: now
        )

        dismissalTasks[activity.id]?.cancel()
        activities.removeAll { $0.id == activity.id }
        activities.insert(activity, at: 0)
        activities = Array(activities.prefix(6))

        if explicitTitle == nil {
            let transcriptPath = object["transcript_path"] as? String
            Task { [weak self, chatTitles] in
                guard let title = await chatTitles.resolve(provider: resolvedProvider, sessionID: sessionID, transcriptPath: transcriptPath),
                      let self else { return }
                // A late lookup must not overwrite a newer hook's explicit name
                // or resurrect a completed/dismissed activity.
                if let index = self.activities.firstIndex(where: { $0.id == activityID && $0.updatedAt == now }) {
                    self.activities[index].title = title
                }
                if let runID = self.historyRuns[activityID]?.id,
                   let index = self.history.firstIndex(where: { $0.id == runID && $0.endedAt == now }) {
                    self.history[index].title = title
                    Defaults[.agentHistory] = self.history
                }
            }
        }

        if state == .completed || state == .interrupted || state == .usageLimited {
            dismissalTasks[activity.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(state == .usageLimited ? 3 : 4))
                guard !Task.isCancelled else { return }
                self?.activities.removeAll { $0.id == activity.id }
                self?.dismissalTasks[activity.id] = nil
            }
        } else if state == .working {
            // If an agent exits without a final hook (for example after a network
            // or quota failure), do not leave a permanent "working" activity.
            dismissalTasks[activity.id] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { return }
                self?.activities.removeAll { $0.id == activity.id }
                self?.dismissalTasks[activity.id] = nil
            }
        }

        let cutoff = Date().addingTimeInterval(-300)
        activities.removeAll { $0.state == .completed && $0.updatedAt < cutoff }
    }

    private static func flattenedStrings(in value: Any) -> [String] {
        switch value {
        case let string as String:
            return [string]
        case let dictionary as [String: Any]:
            return dictionary.flatMap { flattenedStrings(in: $0.value) }
        case let array as [Any]:
            return array.flatMap(flattenedStrings(in:))
        default:
            return []
        }
    }

    /// Low-usage notices such as "15% remaining" are advisory and must not
    /// replace an active task with the brief red limit-reached activity.
    private static func indicatesUsageLimitReached(event: String, payload: String) -> Bool {
        let normalizedEvent = event.lowercased()
        if normalizedEvent == "usagelimit" || normalizedEvent == "ratelimit" {
            return true
        }

        if containsNonzeroRemainingUsage(in: payload) {
            return false
        }

        let exhaustedPhrases = [
            "usage limit reached", "rate limit reached", "limit reached",
            "reached your usage limit", "reached your rate limit",
            "rate_limit_exceeded", "rate_limit_error", "quota exceeded",
            "insufficient_quota", "resource_exhausted", "usage exhausted",
            "too many requests", "limit has been reached", "limit was reached",
            "weekly limit reached", "five hour limit reached", "5-hour limit reached",
            "you've hit your", "you have hit your", "you hit your",
            "you've reached your limit", "you have reached your limit",
            "out of tokens", "tokens exhausted", "token budget exhausted",
            "token limit reached", "zero tokens left", "0 tokens left",
            "usage has been exhausted", "no usage remaining", "no tokens remaining",
            "0% left", "0% remaining", "try again later"
        ]
        return exhaustedPhrases.contains { payload.contains($0) }
    }

    private static func containsNonzeroRemainingUsage(in payload: String) -> Bool {
        let pattern = #"\b(?:[1-9]|[1-9][0-9]|100)\s*%[^.\n]{0,100}\b(?:left|remaining)\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(payload.startIndex..., in: payload)
        return expression.firstMatch(in: payload, range: range) != nil
    }
}

private extension Data {
    var httpRequestPath: String {
        guard
            let request = String(data: self, encoding: .utf8),
            let firstLine = request.split(separator: "\n", maxSplits: 1).first
        else { return "/codex" }

        let parts = firstLine.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : "/codex"
    }

    var httpBody: Data {
        guard let range = range(of: Data("\r\n\r\n".utf8)) else { return self }
        return subdata(in: range.upperBound..<endIndex)
    }

    var containsHTTPBody: Bool {
        guard
            let headerRange = range(of: Data("\r\n\r\n".utf8)),
            let headers = String(data: self[..<headerRange.lowerBound], encoding: .utf8)
        else { return false }

        let contentLength = headers
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") }
            ?? 0
        return count - headerRange.upperBound >= contentLength
    }
}
