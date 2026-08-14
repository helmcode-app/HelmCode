//
//  AgentModels.swift
//  HelmCode
//
//  UI-facing agent controller types: phases, composer controls, timeline stages,
//  and EventLog nodes derived from session history / TaskProgressEvent.
//

import Foundation

// MARK: - Event stages (timeline badges)

/// Structured orchestration stages used by the chat transcript.
enum AgentEventStage: String, Codable, Sendable, CaseIterable, Identifiable {
    case accepted
    case worktreeReady = "worktree_ready"
    case contextBuilt = "context_built"
    case llmInvoke = "llm_invoke"
    case llmPatched = "llm_patched"
    case testing
    case testPassed = "test_passed"
    case testFailed = "test_failed"
    case selfHealing = "self_healing"
    case committing
    case pushing
    case success
    case failed
    case cancelled

    /// Backend / client aliases accepted during decode.
    case provisioning
    case selfHealingActive = "self_healing_active"
    case gitPushed = "git_pushed"

    /// Client-only: the prompt the user sent (not emitted by runner-core).
    case userCommand = "user_command"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .userCommand: return "You"
        case .accepted: return "Accepted"
        case .worktreeReady, .provisioning: return "Provisioning"
        case .contextBuilt: return "Context"
        case .llmInvoke: return "Assistant"
        case .llmPatched: return "Patched"
        case .testing: return "Testing"
        case .testPassed: return "Tests Green"
        case .testFailed: return "Test Failed"
        case .selfHealing, .selfHealingActive: return "Self-Healing"
        case .committing: return "Committing"
        case .pushing: return "Pushing"
        case .success, .gitPushed: return "Pushed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let known = AgentEventStage(rawValue: raw) {
            self = known
            return
        }
        // Forward-compat: unknown stages surface as provisioning so the UI stays live.
        self = .provisioning
    }
}

// MARK: - Controller phase (UI state machine)

/// High-level Agent Command Panel lifecycle (distinct from wire `TaskStatus`).
enum AgentControllerPhase: Equatable, Sendable {
    case idle
    case connecting
    case ready
    case launching
    case processing
    case succeeded
    case failed(String)
    case cancelled

    /// True only while an agent **turn** is in flight (not link handshake).
    ///
    /// Important: `.connecting` must NOT be busy — otherwise a successful health
    /// check never transitions to `.ready` (`if !phase.isBusy { phase = .ready }`).
    var isBusy: Bool {
        switch self {
        case .launching, .processing: return true
        default: return false
        }
    }

    /// Link is still establishing / reconnecting (UI chrome only).
    var isLinking: Bool {
        switch self {
        case .connecting: return true
        default: return false
        }
    }

    var isProcessingLayout: Bool {
        switch self {
        case .launching, .processing: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .ready: return "Ready"
        case .launching: return "Launching"
        case .processing: return "Processing"
        case .succeeded: return "Success"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Composer controls (Cursor-style)

/// Interaction mode for the agent command bar.
enum AgentComposerMode: String, CaseIterable, Identifiable, Sendable {
    case agent
    case plan
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return "Agent"
        case .plan: return "Plan"
        case .ask: return "Ask"
        }
    }

    var systemImage: String {
        switch self {
        case .agent: return "hammer.fill"
        case .plan: return "list.bullet.clipboard"
        case .ask: return "bubble.left.and.bubble.right"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .agent: return "Describe a coding task for the agent…"
        case .plan: return "What should we plan before changing code?"
        case .ask: return "Ask about this codebase…"
        }
    }

    /// Modes the composer should offer. Ask is hidden unless the harness advertised it.
    static func available(advertised: [String]) -> [AgentComposerMode] {
        let ids = Set(advertised.map { $0.lowercased() })
        return allCases.filter { mode in
            switch mode {
            case .agent:
                return true
            case .plan:
                return ids.isEmpty || ids.contains("plan")
            case .ask:
                return ids.contains("ask")
            }
        }
    }
}

/// Selectable model labels for the composer (`provider/model` for `/v1/sessions` prompt).
/// Prefer live catalog from `GET /v1/sessions/models` (connected providers only).
struct AgentModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Provider display name (e.g. "OpenCode Go") — section headers / grouping.
    let subtitle: String

    /// Fallback when runner catalog is unavailable.
    static let fallbackCatalog: [AgentModelOption] = [
        .init(id: "opencode-go/glm-5.1", title: "glm-5.1", subtitle: "opencode-go"),
    ]

    static let defaultID = "opencode-go/glm-5.1"

    /// Wire id shown under the title in lists (`opencode-go/glm-5.1`).
    var wireID: String { id }

    static func title(for id: String, in catalog: [AgentModelOption] = fallbackCatalog) -> String {
        catalog.first { $0.id == id }?.title ?? id
    }

    static func fromDTO(_ dto: SessionModelDTO) -> AgentModelOption {
        AgentModelOption(id: dto.id, title: dto.name, subtitle: dto.provider)
    }

    static func fromResponse(_ response: SessionModelsResponse) -> [AgentModelOption] {
        response.models.map(fromDTO)
    }

    /// Prefer the runner default, then the first catalog row (harness-agnostic).
    static func preferredDefaultID(
        in catalog: [AgentModelOption],
        serverDefault: String?
    ) -> String? {
        if let serverDefault, catalog.contains(where: { $0.id == serverDefault }) {
            return serverDefault
        }
        return catalog.first?.id
    }

    /// Group by provider name, sorted for Settings lists.
    static func groupedByProvider(
        _ models: [AgentModelOption]
    ) -> [(provider: String, models: [AgentModelOption])] {
        let groups = Dictionary(grouping: models, by: \.subtitle)
        return groups.keys.sorted().map { key in
            (
                provider: key,
                models: (groups[key] ?? []).sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            )
        }
    }

    static func matching(_ models: [AgentModelOption], query: String) -> [AgentModelOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return models }
        return models.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.id.localizedCaseInsensitiveContains(q)
                || $0.subtitle.localizedCaseInsensitiveContains(q)
        }
    }
}

// MARK: - EventLog (UI timeline node)

/// UI-facing timeline node derived from wire `TaskProgressEvent` / session history.
struct EventLog: Identifiable, Equatable, Sendable, Hashable {
    let id: String
    let taskId: String
    let status: TaskStatus
    let stage: AgentEventStage?
    let cycle: Int?
    let message: String
    let at: String
    let detail: [String: JSONValue]?
    let arrivedAt: Date

    var timestamp: Date {
        ISO8601DateFormatter.helm.date(from: at)
            ?? ISO8601DateFormatter.helmNoFraction.date(from: at)
            ?? arrivedAt
    }

    init(from event: TaskProgressEvent, sequence: Int = 0) {
        // Prefer stable server message id so streaming updates replace in place.
        if let timelineId = event.detail?["timelineId"]?.stringValue, !timelineId.isEmpty {
            self.id = "tl:\(timelineId)"
        } else {
            self.id = "\(event.taskId)|\(event.at)|\(event.stage?.rawValue ?? event.status.rawValue)|\(sequence)|\(event.message.hashValue)"
        }
        self.taskId = event.taskId
        self.status = event.status
        self.stage = event.stage
        self.cycle = event.cycle
        self.message = event.message
        self.at = event.at
        self.detail = event.detail
        self.arrivedAt = Date()
    }

    /// In-place update for streaming assistant text (same timeline id).
    func updating(message: String, detail: [String: JSONValue]?, status: TaskStatus) -> EventLog {
        EventLog(
            id: id,
            taskId: taskId,
            status: status,
            stage: stage,
            cycle: cycle,
            message: message,
            at: at,
            detail: detail ?? self.detail,
            arrivedAt: arrivedAt
        )
    }

    private init(
        id: String,
        taskId: String,
        status: TaskStatus,
        stage: AgentEventStage?,
        cycle: Int?,
        message: String,
        at: String,
        detail: [String: JSONValue]?,
        arrivedAt: Date
    ) {
        self.id = id
        self.taskId = taskId
        self.status = status
        self.stage = stage
        self.cycle = cycle
        self.message = message
        self.at = at
        self.detail = detail
        self.arrivedAt = arrivedAt
    }
}

// MARK: - Wire timestamps

extension Date {
    /// Parse OpenCode / wire timestamps: ISO-8601, epoch seconds, or epoch ms.
    static func helmParseWire(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let ms = Double(raw), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        if let sec = Double(raw), sec > 1_000_000_000 {
            return Date(timeIntervalSince1970: sec)
        }
        return ISO8601DateFormatter.helm.date(from: raw)
            ?? ISO8601DateFormatter.helmNoFraction.date(from: raw)
    }
}

extension ISO8601DateFormatter {
    static let helmNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
