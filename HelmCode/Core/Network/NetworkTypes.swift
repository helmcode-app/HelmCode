//
//  NetworkTypes.swift
//  HelmCode
//
//  Connection state and HTTP errors for the runner probe.
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

enum HelmNetworkError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case http(Int, String)
    case decoding(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid backend URL."
        case .invalidResponse: return "Unexpected HTTP response."
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .decoding(let msg): return "Decode error: \(msg)"
        case .cancelled: return "Request cancelled."
        }
    }
}
