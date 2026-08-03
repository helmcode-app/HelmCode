//
//  AgentModels.swift
//  HelmCode
//
//  Codable contracts for runner-core WebSocket agent control plane
//  (`agent/run`, `agent/status`, `agent/cancel`, `agent/progress`, `agent/done`).
//  Aligned with services/runner/src/types.ts + agentEngine / agentRouter.
//

import Foundation

// MARK: - Event stages (timeline badges)

/// Structured orchestration stages from `HelmCodeAgentEngine` timeline events.
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .accepted: return "Accepted"
        case .worktreeReady, .provisioning: return "Provisioning"
        case .contextBuilt: return "Context"
        case .llmInvoke: return "LLM"
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

    /// Visual family used by timeline badges.
    var badgeKind: AgentTimelineBadgeKind {
        switch self {
        case .accepted, .worktreeReady, .provisioning, .contextBuilt, .llmInvoke, .llmPatched, .testing, .committing, .pushing:
            return .provisioning
        case .testFailed, .selfHealing, .selfHealingActive, .failed:
            return .warning
        case .testPassed, .success, .gitPushed:
            return .success
        case .cancelled:
            return .cancelled
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

enum AgentTimelineBadgeKind: Sendable, Equatable {
    case provisioning
    case warning
    case success
    case cancelled
    case neutral
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

    /// True only while an agent **task** is in flight (not socket handshake).
    ///
    /// Important: `.connecting` must NOT be busy — otherwise a successful WS
    /// handshake never transitions to `.ready` (`if !phase.isBusy { phase = .ready }`).
    var isBusy: Bool {
        switch self {
        case .launching, .processing: return true
        default: return false
        }
    }

    /// Socket is still establishing / reconnecting (UI chrome only).
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
}

/// Selectable model labels for the composer (sent as task metadata).
struct AgentModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    static let catalog: [AgentModelOption] = [
        .init(id: "gpt-4o", title: "GPT-4o", subtitle: "OpenAI"),
        .init(id: "gpt-4.1", title: "GPT-4.1", subtitle: "OpenAI"),
        .init(id: "claude-sonnet-4", title: "Claude Sonnet", subtitle: "Anthropic"),
        .init(id: "claude-opus-4", title: "Claude Opus", subtitle: "Anthropic"),
        .init(id: "grok-3", title: "Grok 3", subtitle: "xAI"),
        .init(id: "gemini-2.5-pro", title: "Gemini 2.5 Pro", subtitle: "Google"),
    ]

    static let defaultID = "gpt-4o"

    static func title(for id: String) -> String {
        catalog.first { $0.id == id }?.title ?? id
    }
}

// MARK: - agent/run params + envelopes

/// JSON-RPC `agent/run` params (`AgentRunParams` in runner-core).
struct AgentRunParams: Codable, Sendable, Equatable {
    var taskId: String
    var prompt: String
    var baseBranch: String?
    var testCommand: String?
    var contextPaths: [String]?
    var githubToken: String?
    var maxCycles: Int?
    var repoPath: String?
    var remote: String?
    var timeoutMs: Int?
    var metadata: [String: JSONValue]?

    init(
        taskId: String = UUID().uuidString,
        prompt: String,
        baseBranch: String? = nil,
        testCommand: String? = nil,
        contextPaths: [String]? = nil,
        githubToken: String? = nil,
        maxCycles: Int? = 3,
        repoPath: String? = nil,
        remote: String? = nil,
        timeoutMs: Int? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.taskId = taskId
        self.prompt = prompt
        self.baseBranch = baseBranch
        self.testCommand = testCommand
        self.contextPaths = contextPaths
        self.githubToken = githubToken
        self.maxCycles = maxCycles
        self.repoPath = repoPath
        self.remote = remote
        self.timeoutMs = timeoutMs
        self.metadata = metadata
    }

    static func launch(
        prompt: String,
        contextPaths: [String],
        baseBranch: String?,
        testCommand: String?,
        githubToken: String?,
        maxCycles: Int = 3,
        mode: AgentComposerMode = .agent,
        modelID: String = AgentModelOption.defaultID
    ) -> AgentRunParams {
        AgentRunParams(
            taskId: UUID().uuidString.lowercased(),
            prompt: prompt,
            baseBranch: baseBranch.flatMap { $0.isEmpty ? nil : $0 },
            testCommand: testCommand.flatMap { $0.isEmpty ? nil : $0 },
            contextPaths: contextPaths.isEmpty ? nil : contextPaths,
            githubToken: githubToken.flatMap { $0.isEmpty ? nil : $0 },
            maxCycles: maxCycles,
            metadata: [
                "source": .string("helmcode-ipad"),
                "client": .string("HelmCode"),
                "mode": .string(mode.rawValue),
                "model": .string(modelID),
            ]
        )
    }
}

/// Immediate async result from `agent/run`.
struct AgentRunAccepted: Codable, Sendable, Equatable {
    let taskId: String
    let status: String
    let branch: String
    let poll: String?
    let cancel: String?
}

/// Live snapshot from `agent/status` (`AgentTaskSnapshot`).
struct AgentTaskSnapshot: Codable, Sendable, Equatable {
    let taskId: String
    let status: TaskStatus
    let branch: String
    let events: [TaskProgressEvent]
    let result: AgentResult?
    let active: Bool
}

/// Terminal notification `agent/done` params.
struct AgentDoneNotification: Codable, Sendable, Equatable {
    let taskId: String
    /// Wire may say `success` instead of `succeeded`.
    let status: String
    let result: AgentResult?
    let error: String?
}

// MARK: - EventLog (UI timeline node)

/// UI-facing timeline node derived from wire `TaskProgressEvent`.
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

    var badgeKind: AgentTimelineBadgeKind {
        if let stage {
            return stage.badgeKind
        }
        return status.timelineBadgeKind
    }

    var stageLabel: String {
        if let stage { return stage.displayName.uppercased() }
        return status.displayName.uppercased()
    }

    /// Long terminal dumps live in message + detail stderr/stdout.
    var logBody: String {
        var lines: [String] = [message]
        if let detail {
            if let stderr = detail["stderr"]?.stringValue, !stderr.isEmpty {
                lines.append("--- stderr ---")
                lines.append(stderr)
            }
            if let stdout = detail["stdout"]?.stringValue, !stdout.isEmpty {
                lines.append("--- stdout ---")
                lines.append(stdout)
            }
        }
        return lines.joined(separator: "\n")
    }

    init(from event: TaskProgressEvent, sequence: Int = 0) {
        self.id = "\(event.taskId)|\(event.at)|\(event.stage?.rawValue ?? event.status.rawValue)|\(sequence)|\(event.message.hashValue)"
        self.taskId = event.taskId
        self.status = event.status
        self.stage = event.stage
        self.cycle = event.cycle
        self.message = event.message
        self.at = event.at
        self.detail = event.detail
        self.arrivedAt = Date()
    }
}

// MARK: - TaskStatus timeline helpers

extension TaskStatus {
    var timelineBadgeKind: AgentTimelineBadgeKind {
        switch self {
        case .queued, .running, .testing, .committing, .pushing:
            return .provisioning
        case .healing, .failed:
            return .warning
        case .succeeded:
            return .success
        case .cancelled:
            return .cancelled
        }
    }
}

// MARK: - ISO8601 without fractional seconds

extension ISO8601DateFormatter {
    static let helmNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
