//
//  AgentConfigModels.swift
//  HelmCode
//
//  Codable contracts for runner-core `GET/PUT/DELETE /v1/agent`.
//

import Foundation

// MARK: - Catalog / view

enum AgentHarnessID: String, Codable, Sendable, CaseIterable, Identifiable {
    case opencode
    case claude
    case codex
    case cursor
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opencode: return "OpenCode"
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .cursor: return "Cursor CLI"
        case .grok: return "Grok Build"
        }
    }

    var subtitle: String {
        switch self {
        case .opencode: return "Multi-provider ACP shell"
        case .claude: return "via Claude Agent ACP adapter"
        case .codex: return "via Codex ACP adapter"
        case .cursor: return "Native Cursor ACP"
        case .grok: return "Native Grok ACP"
        }
    }

    var needsProvider: Bool { self == .opencode }

    var systemImage: String {
        switch self {
        case .opencode: return "shippingbox"
        case .claude: return "brain.head.profile"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .grok: return "sparkles"
        }
    }
}

enum AgentProviderID: String, Codable, Sendable, CaseIterable, Identifiable {
    case opencodeGo = "opencode-go"
    case opencodeGoPlus = "opencode-go-plus"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opencodeGo: return "Go"
        case .opencodeGoPlus: return "Go Plus"
        }
    }
}

enum AgentRuntimePhase: String, Codable, Sendable, CaseIterable, Identifiable {
    case disabled
    case starting
    case ready
    case error
    case stopped

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .disabled: return "Off"
        case .starting: return "Starting"
        case .ready: return "Ready"
        case .error: return "Error"
        case .stopped: return "Stopped"
        }
    }
}

enum AgentConfigSource: String, Codable, Sendable {
    case file
    case env
    case none
}

struct AgentHarnessCatalogEntry: Codable, Sendable, Equatable, Identifiable {
    let id: AgentHarnessID
    let providers: String
    let impliedProvider: String
    let apiKeyEnv: String?

    var needsProvider: Bool { providers == "required" }
}

/// `GET /v1/agent` / `PUT /v1/agent` response (keys redacted).
struct AgentConfigView: Codable, Sendable, Equatable {
    let enabled: Bool
    let harness: AgentHarnessID?
    let provider: AgentProviderID?
    let defaultModel: String?
    let hasApiKey: Bool
    let apiKeyHint: String?
    let source: AgentConfigSource
    let phase: AgentRuntimePhase
    let error: String?
    let harnesses: [AgentHarnessCatalogEntry]
}

// MARK: - Update body

/// `PUT /v1/agent` body. Omitting `apiKey` keeps the stored key.
struct AgentConfigUpdateBody: Encodable, Sendable {
    var enabled: Bool
    var harness: AgentHarnessID
    var provider: AgentProviderID?
    /// `nil` = omit (keep previous); non-nil including `""` replaces / clears.
    var apiKey: String?
    var defaultModel: String?

    enum CodingKeys: String, CodingKey {
        case enabled, harness, provider, apiKey, defaultModel
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(harness, forKey: .harness)
        try c.encodeIfPresent(provider, forKey: .provider)
        try c.encodeIfPresent(apiKey, forKey: .apiKey)
        try c.encodeIfPresent(defaultModel, forKey: .defaultModel)
    }
}
