//
//  NetworkTypes.swift
//  HelmCode
//
//  Connection / task phase / errors for the runner-core network engine.
//

import Foundation

enum BackendConnectionState: Equatable, Sendable {
    case unknown
    case checking
    case online
    case offline(String)

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    var shortTitle: String {
        switch self {
        case .online: return "Online"
        case .checking: return "Checking…"
        case .offline(let msg): return "Offline — \(msg)"
        case .unknown: return "Not connected"
        }
    }
}

enum EngineTaskPhase: Equatable, Sendable {
    case idle
    case submitting
    case running
    case succeeded
    case failed(String)
    case cancelled

    var isBusy: Bool {
        switch self {
        case .submitting, .running: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .submitting: return "Submitting"
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

enum HelmNetworkError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case http(Int, String)
    case decoding(String)
    case emptyPrompt
    case promptTooLong(limit: Int)
    case concurrentLimit(limit: Int)
    case alreadyRunning
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid backend URL."
        case .invalidResponse: return "Unexpected HTTP response."
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding(let msg): return "Decode error: \(msg)"
        case .emptyPrompt: return "Prompt is required."
        case .promptTooLong(let limit): return "Prompt exceeds \(limit) characters for this mode."
        case .concurrentLimit(let limit): return "Concurrent task limit reached (\(limit))."
        case .alreadyRunning: return "A task is already in flight."
        case .cancelled: return "Request cancelled."
        }
    }
}
