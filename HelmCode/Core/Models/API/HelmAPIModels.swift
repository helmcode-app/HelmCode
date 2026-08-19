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

/// `GET /health` → `HealthStatus` (runner-core open-core).
struct HealthCheck: Codable, Sendable, Equatable {
    let ok: Bool
    let mode: HelmMode
    let version: String
    let uptimeMs: Int
    let sessionsEnabled: Bool?
}

/// `GET /v1/status`
struct RuntimeStatus: Codable, Sendable, Equatable {
    let mode: HelmMode
    let version: String
    let authRequired: Bool?
    let sessionsEnabled: Bool?
    let sessionsManaged: Bool?
    let agentHarness: String?
    let agentTransport: String?
    let vfsEnabled: Bool?
    let terminalEnabled: Bool?
    let defaultWorkspaceId: String?
}

// MARK: - Timeline / result (session history → EventLog)

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

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var stringArrayValue: [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap(\.stringValue)
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var numberValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var intValue: Int? {
        numberValue.map { Int($0) }
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
