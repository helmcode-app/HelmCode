//
//  HelmAPIModels.swift
//  HelmCode
//
//  Codable contracts aligned with runner-core `src/types.ts` + open-core HTTP API.
//

import Foundation

// MARK: - Enums

/// Mirrors `HELM_MODE` / `HelmMode` from runner-core.
enum HelmMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case openCore = "open-core"
    case commercialSaaS = "commercial-saas"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openCore: return "Open Core"
        case .commercialSaaS: return "Commercial SaaS"
        }
    }

    var concurrentTaskLimit: Int {
        switch self {
        case .openCore: return 4
        case .commercialSaaS: return 12
        }
    }

    var promptCharacterLimit: Int {
        switch self {
        case .openCore: return 8_000
        case .commercialSaaS: return 32_000
        }
    }
}

/// Full agent lifecycle — poll `status` + event `status`.
enum TaskStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case queued, running, testing, healing, committing, pushing
    case succeeded, failed, cancelled

    var id: String { rawValue }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled: return true
        default: return false
        }
    }

    var isInFlight: Bool { !isTerminal }

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Health / Status

/// `GET /health` → `HealthStatus`
struct HealthCheck: Codable, Sendable, Equatable {
    let ok: Bool
    let mode: HelmMode
    let version: String
    let uptimeMs: Int
    let activeTasks: Int
}

/// `GET /v1/status`
struct RuntimeStatus: Codable, Sendable, Equatable {
    let mode: HelmMode
    let version: String
    let activeTasks: Int
    let knownTasks: Int
    let authRequired: Bool?
}

// MARK: - Task request / accept

/// `POST /v1/tasks` and `POST /v1/tasks/sync` (`OpenCoreSubmitBody`).
struct TaskRequest: Codable, Sendable, Equatable {
    var prompt: String
    var id: String?
    var baseBranch: String?
    var testCommand: String?
    var contextPaths: [String]?
    var timeoutMs: Int?
    var metadata: [String: JSONValue]?

    init(
        prompt: String,
        id: String? = nil,
        baseBranch: String? = nil,
        testCommand: String? = nil,
        contextPaths: [String]? = nil,
        timeoutMs: Int? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.prompt = prompt
        self.id = id
        self.baseBranch = baseBranch
        self.testCommand = testCommand
        self.contextPaths = contextPaths
        self.timeoutMs = timeoutMs
        self.metadata = metadata
    }

    static func commander(
        prompt: String,
        baseBranch: String = "main",
        contextPaths: [String] = []
    ) -> TaskRequest {
        TaskRequest(
            prompt: prompt,
            baseBranch: baseBranch,
            contextPaths: contextPaths.isEmpty ? nil : contextPaths,
            metadata: [
                "source": .string("helmcode-ipad"),
                "client": .string("HelmCode"),
            ]
        )
    }
}

/// `202 Accepted` from `POST /v1/tasks`
struct TaskAcceptedResponse: Codable, Sendable, Equatable {
    let id: String
    let status: TaskStatus
    let poll: String
    let cancel: String?
}

// MARK: - Poll / result

/// `GET /v1/tasks/:id`
struct TaskPollResponse: Codable, Sendable, Equatable {
    let id: String
    let status: TaskStatus
    let result: AgentResult?
    let events: [TaskProgressEvent]
}

struct AgentResult: Codable, Sendable, Equatable, Identifiable {
    var id: String { taskId }

    let taskId: String
    let status: TaskStatus
    let branch: String
    let worktreePath: String
    let commitSha: String?
    let pushRemote: String?
    let testAttempts: [TestAttempt]
    let summary: String
    let error: String?
    let startedAt: String
    let finishedAt: String
    let durationMs: Int
}

struct TestAttempt: Codable, Sendable, Equatable {
    let attempt: Int
    let result: CommandResult
    let healed: Bool
}

struct CommandResult: Codable, Sendable, Equatable {
    let command: String
    let cwd: String
    let exitCode: Int
    let stdout: String
    let stderr: String
    let durationMs: Int
}

struct TaskProgressEvent: Codable, Sendable, Equatable, Identifiable {
    var id: String {
        let stageKey = stage?.rawValue ?? status.rawValue
        let cycleKey = cycle.map(String.init) ?? "-"
        return "\(taskId)-\(at)-\(stageKey)-\(cycleKey)-\(message.hashValue)"
    }

    let taskId: String
    let status: TaskStatus
    let message: String
    let at: String
    /// Structured orchestration stage from `HelmCodeAgentEngine` timeline.
    let stage: AgentEventStage?
    /// 1-based self-heal / test cycle when applicable.
    let cycle: Int?
    let detail: [String: JSONValue]?

    init(
        taskId: String,
        status: TaskStatus,
        message: String,
        at: String,
        stage: AgentEventStage? = nil,
        cycle: Int? = nil,
        detail: [String: JSONValue]? = nil
    ) {
        self.taskId = taskId
        self.status = status
        self.message = message
        self.at = at
        self.stage = stage
        self.cycle = cycle
        self.detail = detail
    }

    var timestamp: Date {
        ISO8601DateFormatter.helm.date(from: at)
            ?? ISO8601DateFormatter.helmNoFraction.date(from: at)
            ?? .distantPast
    }
}

struct TaskCancelResponse: Codable, Sendable, Equatable {
    let id: String
    let status: TaskStatus
    let message: String
}

struct APIErrorBody: Codable, Sendable, Equatable {
    let error: String
    let status: TaskStatus?
}

// MARK: - JSONValue

enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - Formatting

extension ISO8601DateFormatter {
    static let helm: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
