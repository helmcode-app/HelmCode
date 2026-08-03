//
//  AgentJSONRPC.swift
//  HelmCode
//
//  Agent WebSocket JSON-RPC wire types + engine errors / socket state.
//  Reuses VFS JSON-RPC id / error body (same JSON-RPC 2.0 envelope).
//

import Foundation

// MARK: - Socket state

/// Connection state for the agent control WebSocket (`/v1/agent`).
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
        case .connecting: return "Connecting to /v1/agent…"
        case .connected: return "Agent link ready"
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
    case rpc(code: Int, message: String)
    case timeout
    case closed(String)
    case emptyPrompt
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid agent WebSocket URL."
        case .notConnected: return "Agent WebSocket is not connected."
        case .encoding(let m): return "Agent encode error: \(m)"
        case .decoding(let m): return "Agent decode error: \(m)"
        case .rpc(let code, let message): return "Agent RPC \(code): \(message)"
        case .timeout: return "Agent request timed out."
        case .closed(let m): return "Agent socket closed: \(m)"
        case .emptyPrompt: return "Prompt is required."
        case .alreadyRunning: return "An agent task is already in flight."
        }
    }
}

// MARK: - Wire envelopes

enum AgentJSONRPC {
    static let version = "2.0"
}

struct AgentJSONRPCRequest<P: Encodable>: Encodable {
    let jsonrpc: String = AgentJSONRPC.version
    let id: Int
    let method: String
    let params: P
}

/// Inbound frame: response (has `id`) or notification (method, no usable id).
struct AgentJSONRPCInbound: Decodable {
    let jsonrpc: String?
    let id: VFSJSONRPCID?
    let method: String?
    let result: JSONValue?
    let error: VFSJSONRPCErrorBody?
    let params: JSONValue?

    var isNotification: Bool {
        method != nil && id == nil
    }

    var isResponse: Bool {
        id != nil
    }
}

struct AgentJSONRPCResultBox<T: Decodable>: Decodable {
    let result: T
}
