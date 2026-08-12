//
//  AgentTurnCard.swift
//  HelmCode
//
//  One agent turn: collapsed thought, tool rows, answer, Worked-for / Done footer.
//

import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentTurnCard: View {
    let parts: [EventLog]
    /// Show green Done on the Worked-for row (only the latest completed turn).
    var showDone: Bool = false
    var onUndoRestore: (() -> Void)? = nil

    @State private var thoughtExpanded = false
    @State private var expandedToolIDs: Set<String> = []
    @State private var now = Date()

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
                if AgentChatFormatting.looksLikeRawToolNoise(msg) { continue }
                intermediateAnswers.append(msg)
            }
        }

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
            tools: AgentToolAction.dedupe(tools),
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

    private var isRunning: Bool {
        parts.contains { ($0.detail?["done"]?.boolValue ?? true) == false }
            || parts.contains {
                $0.message == "Working…" && ($0.detail?["done"]?.boolValue ?? false) == false
            }
    }

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
        return "Thought for \(AgentChatFormatting.formatDuration(thoughtSeconds))"
    }

    private var workedLabel: String {
        if isRunning {
            if totalSeconds < 0.15 { return "Working…" }
            return "Working · \(AgentChatFormatting.formatDuration(totalSeconds))"
        }
        return "Worked for \(AgentChatFormatting.formatDuration(totalSeconds))"
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
                if !fallback.isEmpty, !AgentChatFormatting.looksLikeRawToolNoise(fallback) {
                    Text(fallback)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 8) {
                Text(workedLabel)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                if showDone, !isRunning {
                    if let onUndoRestore {
                        Button("Undo restore", action: onUndoRestore)
                            .font(.caption.weight(.semibold))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text("Done")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Done")
                }
            }
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
        VStack(alignment: .leading, spacing: 8) {
            ForEach(toolActions) { action in
                AgentToolRow(
                    action: action,
                    isExpanded: expandedToolIDs.contains(action.id),
                    onToggle: {
                        if expandedToolIDs.contains(action.id) {
                            expandedToolIDs.remove(action.id)
                        } else {
                            expandedToolIDs.insert(action.id)
                        }
                    }
                )
            }
        }
        .padding(.vertical, 2)
        .onChange(of: toolActions.map(\.id).joined(separator: "|")) { _, _ in
            autoExpandFileTools()
        }
        .onAppear {
            autoExpandFileTools()
        }
    }

    private func autoExpandFileTools() {
        for action in toolActions where action.hasExpandableBody {
            if action.kind == .edit || action.kind == .write {
                expandedToolIDs.insert(action.id)
            }
        }
    }
}
