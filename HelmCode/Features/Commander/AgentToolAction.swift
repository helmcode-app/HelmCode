//
//  AgentToolAction.swift
//  HelmCode
//
//  Structured tool rows from runner meta.toolActions (pi / Grok harness style):
//    ◇ Read  path/to/file.swift
//      42 lines
//    ◇ Edit  path/to/file.swift
//      +3 / -2
//

import Foundation

enum ToolRowStatus {
    case ok, running, error
}

struct AgentToolAction: Identifiable, Equatable {
    let id: String
    let name: String
    let label: String
    let path: String?
    let content: String?
    let status: String?

    enum Kind {
        case read, write, edit, run, search, list, askQuestion, other
    }

    var kind: Kind {
        let n = name.lowercased()
        if n.contains("ask_user_question") || n.contains("ask-question") || n.contains("ask_question") {
            return .askQuestion
        }
        if n == "read" || n == "view" || n == "cat" { return .read }
        if n == "write" || n == "create" { return .write }
        if n == "edit" || n == "patch" || n.contains("replace") || n.contains("patch") {
            return .edit
        }
        if n == "bash" || n == "shell" || n == "run" || n == "terminal" { return .run }
        if n.contains("search") || n == "grep" || n == "rg" { return .search }
        if n == "list" || n == "glob" || n == "ls" { return .list }
        return .other
    }

    /// pi-style verb: Read / Edit / Write / Run / Ask / …
    var verb: String {
        switch kind {
        case .read: return "Read"
        case .write: return "Write"
        case .edit: return "Edit"
        case .run: return "Run"
        case .search: return "Search"
        case .list: return "List"
        case .askQuestion: return "Ask"
        case .other:
            let first = label.split(separator: " ").first.map(String.init) ?? name
            return first.prefix(1).uppercased() + first.dropFirst()
        }
    }

    /// Path or command detail shown after the verb (accent).
    var detail: String {
        if let path, !path.isEmpty {
            return AgentChatFormatting.shortDisplayPath(path)
        }
        let parts = label.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2 { return parts[1] }
        return label
    }

    var questions: [AgentUserQuestion] {
        guard kind == .askQuestion else { return [] }
        return AgentUserQuestion.parse(from: content)
    }

    var contentLines: [String] {
        guard let content, !content.isEmpty else { return [] }
        return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    var lineCount: Int {
        let lines = contentLines
        guard !lines.isEmpty else { return 0 }
        if lines.count == 1, lines[0].isEmpty { return 0 }
        return lines.count
    }

    /// Diff stats when content looks like unified +/- lines.
    var diffStats: (additions: Int, removals: Int)? {
        let lines = contentLines
        guard !lines.isEmpty else { return nil }
        var add = 0, rem = 0
        var looksLikeDiff = false
        for line in lines {
            if line.hasPrefix("+++") || line.hasPrefix("---") {
                looksLikeDiff = true
                continue
            }
            if line.hasPrefix("+") {
                add += 1
                looksLikeDiff = true
            } else if line.hasPrefix("-") {
                rem += 1
                looksLikeDiff = true
            }
        }
        guard looksLikeDiff, add + rem > 0 else { return nil }
        return (add, rem)
    }

    var statusKind: ToolRowStatus {
        let s = (status ?? "").lowercased()
        if s == "error" || s == "failed" { return .error }
        if s == "pending" || s == "running" || s == "in_progress" || s == "in-progress" {
            return .running
        }
        return .ok
    }

    var hasExpandableBody: Bool {
        guard let content else { return false }
        return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Subtitle under the title row (pi: "42 lines", "+3 / -2").
    var statsLabel: String? {
        if let d = diffStats {
            return "+\(d.additions) / -\(d.removals)"
        }
        if let content, let stats = AgentChatFormatting.parsePlusMinusStats(content) {
            return "+\(stats.add) / -\(stats.del)"
        }
        if kind == .read || kind == .write || kind == .edit, lineCount > 0 {
            return "\(lineCount) line\(lineCount == 1 ? "" : "s")"
        }
        if kind == .run, lineCount > 0 {
            return "\(lineCount) line\(lineCount == 1 ? "" : "s") output"
        }
        return nil
    }

    static func parse(from detail: [String: JSONValue]?) -> [AgentToolAction] {
        guard let raw = detail?["toolActions"]?.arrayValue else { return [] }
        var out: [AgentToolAction] = []
        for (idx, item) in raw.enumerated() {
            guard let o = item.objectValue else { continue }
            let name = o["name"]?.stringValue ?? "tool"
            let label = o["label"]?.stringValue
                ?? ([name.capitalized, o["path"]?.stringValue].compactMap { $0 }.joined(separator: " "))
            let path = o["path"]?.stringValue
            let content = o["content"]?.stringValue
            let status = o["status"]?.stringValue
            let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLabel.isEmpty else { continue }
            out.append(
                AgentToolAction(
                    id: "\(name)-\(path ?? label)-\(idx)",
                    name: name,
                    label: trimmedLabel,
                    path: path,
                    content: content?.isEmpty == true ? nil : content,
                    status: status
                )
            )
        }
        return out
    }

    static func parseLegacyLabels(from detail: [String: JSONValue]?) -> [AgentToolAction] {
        guard let labels = detail?["tools"]?.stringArrayValue else { return [] }
        return labels.enumerated().compactMap { idx, label in
            let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard AgentChatFormatting.isUsefulToolLabel(t) else { return nil }
            let name = inferName(from: t)
            let path = inferPath(from: t)
            return AgentToolAction(
                id: "legacy-\(idx)-\(t)",
                name: name,
                label: t,
                path: path,
                content: nil,
                status: nil
            )
        }
    }

    /// Prefer richer rows when edit + patch both map the same path.
    static func dedupe(_ items: [AgentToolAction]) -> [AgentToolAction] {
        var best: [String: AgentToolAction] = [:]
        var order: [String] = []
        for action in items {
            let kindKey: String = {
                switch action.kind {
                case .edit, .write: return "file-change"
                default: return String(describing: action.kind)
                }
            }()
            let key = "\(kindKey)|\(action.path ?? action.detail)"
            if let existing = best[key] {
                let existingScore = existing.content?.count ?? 0
                let newScore = action.content?.count ?? 0
                if newScore > existingScore
                    || (newScore == existingScore && action.name != "patch" && existing.name == "patch") {
                    best[key] = action
                }
            } else {
                best[key] = action
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    private static func inferName(from label: String) -> String {
        let l = label.lowercased()
        if l.hasPrefix("read") { return "read" }
        if l.hasPrefix("write") { return "write" }
        if l.hasPrefix("edit") || l.hasPrefix("patch") { return "edit" }
        if l.hasPrefix("run") || l.hasPrefix("ran") || l.hasPrefix("bash") { return "bash" }
        if l.hasPrefix("search") { return "search" }
        return "tool"
    }

    private static func inferPath(from label: String) -> String? {
        let parts = label.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        var path = parts[1]
        if let r = path.range(of: " (", options: .backwards) {
            path = String(path[..<r.lowerBound])
        }
        if path.contains("/") || path.contains(".") { return path }
        return nil
    }
}
