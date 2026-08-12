//
//  AgentChatFormatting.swift
//  HelmCode
//
//  Shared pure helpers for Commander chat UI (durations, paths, noise filters).
//

import Foundation

enum AgentChatFormatting {
    /// Compact duration: `1.2s`, `45s`, `1m 05s`, `1h 02m`.
    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 0.5 {
            return "<1s"
        }
        if seconds < 10 {
            return String(format: "%.1fs", seconds)
        }
        if seconds < 60 {
            return String(format: "%.0fs", seconds)
        }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%dh %02dm", h, m)
        }
        return String(format: "%dm %02ds", m, s)
    }

    /// Drop legacy / broken labels like `patch:patch`, bare uuids.
    static func isUsefulToolLabel(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        let lower = t.lowercased()
        if lower == "tool" || lower == "patch" || lower == "edit" || lower == "file" {
            return false
        }
        if lower.range(of: #"^(\w+):\1$"#, options: .regularExpression) != nil {
            return false
        }
        if t.count >= 20, t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
            return false
        }
        return true
    }

    static func looksLikeRawToolNoise(_ msg: String) -> Bool {
        let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[tool:") { return true }
        if t.lowercased().hasPrefix("patch:") { return true }
        if t.range(
            of: #"^(read|edit|write|patch|bash)(/|:)?"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil,
           t.count < 40,
           !t.contains(" ") {
            return true
        }
        return false
    }

    /// pi-style path: keep last 2 segments when long.
    static func shortDisplayPath(_ path: String) -> String {
        let t = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= 56 { return t }
        let parts = t.split(separator: "/").map(String.init)
        if parts.count >= 2 {
            return "…/" + parts.suffix(2).joined(separator: "/")
        }
        return String(t.prefix(55)) + "…"
    }

    static func parsePlusMinusStats(_ content: String) -> (add: Int, del: Int)? {
        let pattern = #"\+(\d+)\s*/\s*-(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        guard let match = regex.firstMatch(in: content, range: range),
              match.numberOfRanges >= 3,
              let addR = Range(match.range(at: 1), in: content),
              let delR = Range(match.range(at: 2), in: content),
              let add = Int(content[addR]),
              let del = Int(content[delR])
        else { return nil }
        return (add, del)
    }
}
