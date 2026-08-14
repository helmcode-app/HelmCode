//
//  SessionModels.swift
//  HelmCode
//
//  Codable contracts for runner-core `/v1/sessions/*` (backend-agnostic).
//  Aligned with runner-core services/runner/src/sessions/types.ts.
//

import Foundation

// MARK: - Session

struct AgentSessionDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let title: String?
    let status: SessionStatusWire
    let createdAt: String?
    let updatedAt: String?
    let backend: String?
    /// ACP mode ids advertised at session/new (`build`, `plan`, …).
    let modes: [String]?
    /// Workspace this session edits (`default` = primary repo).
    let workspaceId: String?
}

enum SessionStatusWire: String, Codable, Sendable {
    case idle
    case running
    case completed
    case failed
    case cancelled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SessionStatusWire(rawValue: raw) ?? .unknown
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .idle: return true
        case .running, .unknown: return false
        }
    }
}

struct CreateSessionBody: Encodable, Sendable {
    var title: String?
    var workspaceId: String?
}

struct CreateSessionEnvelope: Decodable, Sendable {
    let session: AgentSessionDTO
}

struct GetSessionEnvelope: Decodable, Sendable {
    let session: AgentSessionDTO
}

struct ListSessionsEnvelope: Decodable, Sendable {
    let sessions: [AgentSessionDTO]
}

// MARK: - Prompt

struct SessionPromptBody: Encodable, Sendable {
    var prompt: String
    var model: String?
    var mode: String?
    var contextPaths: [String]?
}

struct SessionPromptAccepted: Codable, Sendable, Equatable {
    let sessionId: String
    let status: String
    let mode: String?
    let model: String?
}

// MARK: - History / timeline

struct SessionTimelineEntry: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let at: String?
    let kind: String?
    let role: String?
    let text: String
    let stage: String?
    /// This message finished (`time.completed` / `finish`). Multi-step turns have several rows.
    let done: Bool?
    /// Optional structured extras (`reasoning`, `tools`, `answer`) from the runner mapper.
    let meta: [String: JSONValue]?
}

struct SessionHistoryEnvelope: Codable, Sendable, Equatable {
    let sessionId: String
    let session: AgentSessionDTO?
    let entries: [SessionTimelineEntry]
}

struct SessionCancelResponse: Codable, Sendable, Equatable {
    let sessionId: String
    let cancelled: Bool
}

enum SessionRewindRestore: String, Codable, Sendable {
    case both
    case conversation
    case code
}

struct SessionRewindBody: Encodable, Sendable {
    var messageId: String
    var restore: SessionRewindRestore?
}

struct SessionRewindResponse: Codable, Sendable, Equatable {
    let sessionId: String
    let messageId: String
    let restore: SessionRewindRestore
    let prompt: String
    let session: AgentSessionDTO
    let truncated: Int
    let filesRestored: Bool
    let entries: [SessionTimelineEntry]
}

struct SessionDeleteResponse: Codable, Sendable, Equatable {
    let sessionId: String
    let deleted: Bool
}

struct SessionsRuntimeHealth: Codable, Sendable, Equatable {
    let ok: Bool
    let provider: String?
    let version: String?
    let error: String?
    let harness: String?
}

// MARK: - Models catalog (GET /v1/sessions/models)

struct SessionModelDTO: Codable, Sendable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String
    let connected: Bool?
}

struct SessionModelsResponse: Codable, Sendable, Equatable {
    let models: [SessionModelDTO]
    let defaultModel: String?
    let connected: [String]?
}
