//
//  AgentChatBubbles.swift
//  HelmCode
//
//  Chat transcript chrome (Cursor / other harness style):
//  - User messages: right-aligned bubble, left-aligned text inside
//  - Agent output: flat on the panel background (no bubble card)
//  - "Thought for 1.1s" collapsed (no content preview)
//  - Tool rows: Read/Edit path + expandable file body
//  - "Worked for 1.2s" duration footer
//  - Restore checkpoint only on user messages
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Transcript grouping

enum AgentTranscriptItem: Identifiable, Equatable {
    case user(EventLog)
    /// Consecutive non-user rows after a user prompt (thinking / tools / answer).
    case agentTurn(id: String, parts: [EventLog])

    var id: String {
        switch self {
        case .user(let e): return e.id
        case .agentTurn(let id, _): return "turn:\(id)"
        }
    }

    static func build(from log: [EventLog]) -> [AgentTranscriptItem] {
        var items: [AgentTranscriptItem] = []
        var buffer: [EventLog] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let key = buffer.compactMap { $0.detail?["timelineId"]?.stringValue }
                .filter { !$0.isEmpty }
                .joined(separator: "+")
            let id = key.isEmpty ? buffer.map(\.id).joined(separator: "+") : key
            items.append(.agentTurn(id: id, parts: buffer))
            buffer = []
        }

        for entry in log {
            if entry.stage == .userCommand {
                flushBuffer()
                items.append(.user(entry))
            } else {
                buffer.append(entry)
            }
        }
        flushBuffer()
        return items
    }
}

// MARK: - Structured tool action (from runner meta.toolActions)

struct AgentToolAction: Identifiable, Equatable {
    let id: String
    let name: String
    let label: String
    let path: String?
    let content: String?
    let status: String?

    var isEdit: Bool {
        let n = name.lowercased()
        return n == "edit" || n == "write" || n == "create" || n == "patch"
            || n.contains("replace") || n.contains("patch")
    }

    var isRead: Bool {
        let n = name.lowercased()
        return n == "read" || n == "view" || n == "cat"
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
            // Drop empty noise
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

    /// Fallback when only legacy `tools: [String]` is present.
    static func parseLegacyLabels(from detail: [String: JSONValue]?) -> [AgentToolAction] {
        guard let labels = detail?["tools"]?.stringArrayValue else { return [] }
        return labels.enumerated().compactMap { idx, label in
            let t = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsefulToolLabel(t) else { return nil }
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

    private static func inferName(from label: String) -> String {
        let l = label.lowercased()
        if l.hasPrefix("read") { return "read" }
        if l.hasPrefix("edit") || l.hasPrefix("patch") || l.hasPrefix("write") { return "edit" }
        if l.hasPrefix("ran") || l.hasPrefix("bash") { return "bash" }
        if l.hasPrefix("search") { return "search" }
        return "tool"
    }

    private static func inferPath(from label: String) -> String? {
        // "Read src/foo.ts" / "Edit pkg/bar.go"
        let parts = label.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let path = parts[1]
        if path.contains("/") || path.contains(".") { return path }
        return nil
    }
}

// MARK: - User bubble (only chrome with a bubble; Restore checkpoint lives here)

struct AgentUserBubble: View {
    let entry: EventLog
    var onRevert: (() -> Void)?

    private var messageId: String? {
        guard let mid = entry.detail?["timelineId"]?.stringValue, mid.hasPrefix("msg") else {
            return nil
        }
        return mid
    }

    private var canShowRevert: Bool {
        messageId != nil && onRevert != nil
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Spacer(minLength: 48)

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    // Bubble sits on the right; text inside is left-aligned (other harnesses).
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Color.accentColor.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )

                HStack(spacing: 10) {
                    if canShowRevert, let onRevert {
                        Button(action: onRevert) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderless)
                        .tint(.secondary)
                        .accessibilityLabel("Restore checkpoint")
                        .help("Restore: remove this message and after, put text back in the composer")
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contextMenu {
            if canShowRevert, let onRevert {
                Button(role: .destructive, action: onRevert) {
                    Label("Restore to this message", systemImage: "arrow.uturn.backward.circle")
                }
            }
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = entry.message
                #endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - Agent turn (flat on background — no bubble)

struct AgentTurnCard: View {
    let parts: [EventLog]

    @State private var thoughtExpanded = false
    @State private var expandedToolIDs: Set<String> = []
    /// Live clock while the turn is still running (for elapsed labels).
    @State private var now = Date()

    /// Split multi-step OpenCode rows into thought / tools / final answer.
    private var partitioned: (thought: String, tools: [AgentToolAction], answer: String) {
        var thoughts: [String] = []
        var tools: [AgentToolAction] = []
        var answers: [String] = []
        var intermediateAnswers: [String] = []

        for p in parts {
            let kind = (p.detail?["kind"]?.stringValue ?? "message").lowercased()
            let msg = p.message.trimmingCharacters(in: .whitespacesAndNewlines)

            let structured = AgentToolAction.parse(from: p.detail)
            if !structured.isEmpty {
                tools.append(contentsOf: structured)
            } else {
                tools.append(contentsOf: AgentToolAction.parseLegacyLabels(from: p.detail))
            }

            if let r = p.detail?["reasoning"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !r.isEmpty {
                thoughts.append(r)
            } else if kind == "reasoning", !msg.isEmpty, msg != "Working…" {
                thoughts.append(msg)
            }

            if kind == "tool" || p.stage == .testing {
                // Structured tools already collected; skip raw message noise.
                continue
            }

            if msg.hasPrefix("[tool:") {
                continue
            }

            if let answer = p.detail?["answer"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !answer.isEmpty {
                answers.append(answer)
                continue
            }

            if kind == "message" || kind == "unknown" || kind.isEmpty {
                guard !msg.isEmpty, msg != "Working…" else { continue }
                if let r = p.detail?["reasoning"]?.stringValue, r == msg { continue }
                if looksLikeRawToolNoise(msg) { continue }
                intermediateAnswers.append(msg)
            }
        }

        // Multi-step turns: earlier plain text → thought, last → answer.
        if answers.isEmpty, !intermediateAnswers.isEmpty {
            if intermediateAnswers.count == 1 {
                answers = intermediateAnswers
            } else {
                thoughts.append(contentsOf: intermediateAnswers.dropLast())
                answers = [intermediateAnswers.last!]
            }
        } else if !intermediateAnswers.isEmpty {
            thoughts.append(contentsOf: intermediateAnswers)
        }

        return (
            thought: dedupeJoin(thoughts),
            tools: dedupeTools(tools),
            answer: dedupeJoin(answers)
        )
    }

    private var thoughtText: String { partitioned.thought }
    private var toolActions: [AgentToolAction] { partitioned.tools }
    private var answerText: String { partitioned.answer }

    private func dedupeJoin(_ chunks: [String]) -> String {
        var seen = Set<String>()
        return chunks.filter { seen.insert($0).inserted }.joined(separator: "\n\n")
    }

    private func dedupeTools(_ items: [AgentToolAction]) -> [AgentToolAction] {
        var seen = Set<String>()
        return items.filter { seen.insert("\($0.name)|\($0.path ?? "")|\($0.label)").inserted }
    }

    private var isRunning: Bool {
        parts.contains { ($0.detail?["done"]?.boolValue ?? true) == false }
            || parts.contains {
                $0.message == "Working…" && ($0.detail?["done"]?.boolValue ?? false) == false
            }
    }

    // MARK: Durations

    private var totalSeconds: TimeInterval {
        spanSeconds(for: parts)
    }

    private var thoughtSeconds: TimeInterval {
        let thoughtParts = parts.filter { p in
            let kind = (p.detail?["kind"]?.stringValue ?? "").lowercased()
            if kind == "reasoning" { return true }
            if let r = p.detail?["reasoning"]?.stringValue, !r.isEmpty { return true }
            return false
        }
        if !thoughtParts.isEmpty {
            return max(spanSeconds(for: thoughtParts), 0.1)
        }
        if !thoughtText.isEmpty, totalSeconds > 0 {
            return max(min(totalSeconds * 0.45, totalSeconds - 0.1), 0.1)
        }
        return 0
    }

    private func spanSeconds(for rows: [EventLog]) -> TimeInterval {
        let stamps = rows.map(\.timestamp).filter { $0 != .distantPast }
        let arrived = rows.map(\.arrivedAt)
        var best: TimeInterval = 0
        if let s0 = stamps.min(), let s1 = stamps.max() {
            let end = isRunning ? now : s1
            best = max(best, end.timeIntervalSince(s0))
        }
        if let a0 = arrived.min(), let a1 = arrived.max() {
            let end = isRunning ? now : a1
            best = max(best, end.timeIntervalSince(a0))
        }
        return max(0, best)
    }

    private var thoughtLabel: String {
        if thoughtText.isEmpty { return "" }
        if isRunning, thoughtSeconds < 0.15 {
            return "Thinking…"
        }
        return "Thought for \(formatDuration(thoughtSeconds))"
    }

    private var workedLabel: String {
        if isRunning {
            if totalSeconds < 0.15 { return "Working…" }
            return "Working · \(formatDuration(totalSeconds))"
        }
        return "Worked for \(formatDuration(totalSeconds))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !thoughtText.isEmpty {
                thoughtSection
            }

            if !toolActions.isEmpty {
                toolsSection
            }

            if !answerText.isEmpty {
                Text(answerText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isRunning, thoughtText.isEmpty, toolActions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text("Working…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if answerText.isEmpty, !isRunning, thoughtText.isEmpty, toolActions.isEmpty {
                let fallback = parts.last?.message ?? ""
                if !fallback.isEmpty, !looksLikeRawToolNoise(fallback) {
                    Text(fallback)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            Text(workedLabel)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { date in
            if isRunning { now = date }
        }
        .contextMenu {
            if !answerText.isEmpty {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = answerText
                    #endif
                } label: {
                    Label("Copy answer", systemImage: "doc.on.doc")
                }
            }
            if !thoughtText.isEmpty {
                Button {
                    #if canImport(UIKit)
                    UIPasteboard.general.string = thoughtText
                    #endif
                } label: {
                    Label("Copy thought", systemImage: "brain")
                }
            }
        }
    }

    /// Collapsed = "Thought for 1.1s" only — no content preview (Cursor).
    private var thoughtSection: some View {
        DisclosureGroup(isExpanded: $thoughtExpanded) {
            Text(thoughtText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text(thoughtLabel)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .tint(.secondary)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(toolActions) { action in
                toolRow(action)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func toolRow(_ action: AgentToolAction) -> some View {
        let hasBody = action.content?.isEmpty == false
        let expanded = expandedToolIDs.contains(action.id)

        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard hasBody else { return }
                if expanded {
                    expandedToolIDs.remove(action.id)
                } else {
                    expandedToolIDs.insert(action.id)
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: toolIcon(for: action))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                        if let path = action.path,
                           path != action.label,
                           !action.label.contains(path) {
                            Text(path)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    if hasBody {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasBody)

            if expanded, let content = action.content, !content.isEmpty {
                Text(content)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }
        }
    }

    private func toolIcon(for action: AgentToolAction) -> String {
        if action.isRead { return "doc.text" }
        if action.isEdit { return "pencil" }
        let n = action.name.lowercased()
        if n == "bash" || n == "shell" || n == "run" || n == "terminal" {
            return "terminal"
        }
        if n.contains("search") || n == "grep" || n == "rg" {
            return "magnifyingglass"
        }
        if n == "list" || n == "glob" || n == "ls" {
            return "folder"
        }
        return "wrench.and.screwdriver"
    }
}

// MARK: - Processing strip

struct AgentProcessingBanner: View {
    @ObservedObject var agent: AgentNetworkEngine

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.composerMode == .ask ? "Thinking…" : "Agent is working…")
                    .font(.caption.weight(.semibold))
                Text(agent.pollStatus?.displayName ?? agent.phase.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if agent.phase.isBusy {
                Button("Stop") {
                    Task { await agent.cancelActiveTask() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Helpers

private func formatDuration(_ seconds: TimeInterval) -> String {
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

private func isUsefulToolLabel(_ raw: String) -> Bool {
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

private func looksLikeRawToolNoise(_ msg: String) -> Bool {
    let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.hasPrefix("[tool:") { return true }
    if t.lowercased().hasPrefix("patch:") { return true }
    if t.range(of: #"^(read|edit|write|patch|bash)(/|:)?"#, options: [.regularExpression, .caseInsensitive]) != nil,
       t.count < 40,
       !t.contains(" ") {
        return true
    }
    return false
}
