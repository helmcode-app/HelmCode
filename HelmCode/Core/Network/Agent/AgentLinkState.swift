//
//  AgentLinkState.swift
//  HelmCode
//
//  Agent sessions link state + engine errors for `/v1/sessions/*`.
//

import Foundation

// MARK: - Link state

/// Connection state for the agent sessions runtime (`GET /v1/sessions/health`).
enum AgentSocketState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(String)

    var isReady: Bool {
        if case .connected = self { return true }
        return false
    }

    var shortTitle: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting to sessions…"
        case .connected: return "Agent sessions ready"
        case .reconnecting(let n): return "Reconnecting (\(n))…"
        case .failed(let m): return "Failed — \(m)"
        }
    }
}

// MARK: - Errors

enum AgentEngineError: LocalizedError, Equatable {
    case invalidURL
    case notConnected
    case encoding(String)
    case decoding(String)
    case http(Int, String)
    case timeout
    case closed(String)
    case emptyPrompt
    case alreadyRunning
    case sessionsDisabled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid runner base URL."
        case .notConnected: return "Agent sessions runtime is not connected."
        case .encoding(let m): return "Agent encode error: \(m)"
        case .decoding(let m): return "Agent decode error: \(m)"
        case .http(let code, let message): return "Agent HTTP \(code): \(message)"
        case .timeout: return "Agent request timed out."
        case .closed(let m): return "Agent link closed: \(m)"
        case .emptyPrompt: return "Prompt is required."
        case .alreadyRunning: return "An agent turn is already in flight."
        case .sessionsDisabled:
            return "Agent sessions are disabled on the runner (set OPENCODE_ENABLED=true)."
        }
    }
}
