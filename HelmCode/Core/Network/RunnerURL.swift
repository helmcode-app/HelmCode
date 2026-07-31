//
//  RunnerURL.swift
//  HelmCode
//
//  Normalize / validate runner-core base URLs (HTTP task API + VFS WebSocket).
//

import Foundation

enum RunnerURL {
    private static let httpSchemes: Set<String> = ["http", "https"]
    private static let wsSchemes: Set<String> = ["ws", "wss"]
    private static let acceptedSchemes = httpSchemes.union(wsSchemes)

    /// Trim and map `ws(s)://` → `http(s)://` for the HTTP client / Settings storage.
    static func normalizeHTTP(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("ws://") {
            return "http://" + trimmed.dropFirst(5)
        }
        if trimmed.lowercased().hasPrefix("wss://") {
            return "https://" + trimmed.dropFirst(6)
        }
        return trimmed
    }

    /// Absolute `GET …/health` URL for a runner base string.
    static func healthURL(fromBase raw: String) -> URL? {
        let http = normalizeHTTP(raw)
        guard isValid(http), var components = URLComponents(string: http) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty ? "/health" : "/\(basePath)/health"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// True when the string is a usable runner base (`http`/`https`/`ws`/`wss` + host).
    static func isValid(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased(), acceptedSchemes.contains(scheme) else { return false }
        return url.host != nil
    }

    /// Build `ws(s)://host/…/v1/vfs` from an HTTP or WS base URL string.
    static func webSocketVFSURL(fromBase baseURLString: String) -> URL? {
        guard var components = URLComponents(string: baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "https":
            components.scheme = "wss"
        case "http", .none:
            components.scheme = "ws"
        case "ws", "wss":
            break
        default:
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if basePath.isEmpty {
            components.path = "/v1/vfs"
        } else {
            components.path = "/\(basePath)/v1/vfs"
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
