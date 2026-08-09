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

    /// Normalized HTTP base, or `fallback` when empty / invalid.
    static func httpBase(from raw: String, fallback: String) -> String {
        let normalized = normalizeHTTP(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if !normalized.isEmpty, isValid(normalized) {
            return normalizeHTTP(normalized)
        }
        return normalizeHTTP(fallback)
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
        webSocketURL(fromBase: baseURLString, pathSuffix: "/v1/vfs")
    }

    /// Absolute `GET …/v1/sessions/health` for agent runtime probe.
    static func sessionsHealthURL(fromBase raw: String) -> URL? {
        let http = normalizeHTTP(raw)
        guard isValid(http), var components = URLComponents(string: http) else { return nil }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = basePath.isEmpty
            ? "/v1/sessions/health"
            : "/\(basePath)/v1/sessions/health"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Build `ws(s)://host/…/v1/terminal` for WebSSH (xterm.js / Docker exec TTY).
    static func webSocketTerminalURL(
        fromBase baseURLString: String,
        cols: Int = 80,
        rows: Int = 24,
        token: String? = nil
    ) -> URL? {
        guard let base = webSocketURL(fromBase: baseURLString, pathSuffix: "/v1/terminal"),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        var items = [
            URLQueryItem(name: "cols", value: String(max(1, cols))),
            URLQueryItem(name: "rows", value: String(max(1, rows))),
        ]
        if let token {
            let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                items.append(URLQueryItem(name: "token", value: t))
            }
        }
        components.queryItems = items
        return components.url
    }

    private static func webSocketURL(fromBase baseURLString: String, pathSuffix: String) -> URL? {
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
            components.path = pathSuffix
        } else {
            components.path = "/\(basePath)\(pathSuffix)"
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}
