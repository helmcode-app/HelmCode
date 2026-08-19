//
//  SessionChatTitle.swift
//  HelmCode
//
//  Chat list / header names. First user prompt, like Cursor / Claude —
//  later turns do not rename the session.
//

import Foundation

enum SessionChatTitle {
    static let placeholder = "New chat"

    static func isPlaceholder(_ raw: String?) -> Bool {
        let trimmed = raw?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch trimmed {
        case "", "new chat", "untitled chat", "untitled", "helmcode", "chat", "agent":
            return true
        default:
            return false
        }
    }

    /// Prefer a real remote title; keep a locally generated one over a placeholder.
    static func coalesce(_ remote: String?, _ local: String?) -> String? {
        if let remote, !isPlaceholder(remote) { return remote }
        if let local, !isPlaceholder(local) { return local }
        return remote ?? local
    }

    static func fromUserPrompt(_ prompt: String, maxChars: Int = 72) -> String {
        let line = prompt
            .split(whereSeparator: { $0.isNewline || $0.isWhitespace })
            .joined(separator: " ")
        guard !line.isEmpty else { return placeholder }
        guard line.count > maxChars else { return line }
        return truncate(line, maxChars: maxChars)
    }

    static func display(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? placeholder : trimmed
    }

    private static func truncate(_ line: String, maxChars: Int) -> String {
        let sliced = String(line.prefix(maxChars))
        let punctuation = CharacterSet(charactersIn: ".,;:!? ")
        if let lastSpace = sliced.lastIndex(of: " "),
           sliced.distance(from: sliced.startIndex, to: lastSpace) > maxChars * 55 / 100 {
            return String(sliced[..<lastSpace]).trimmingCharacters(in: punctuation) + "…"
        }
        return sliced.trimmingCharacters(in: punctuation) + "…"
    }
}
