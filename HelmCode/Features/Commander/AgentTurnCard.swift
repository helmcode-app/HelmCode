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
    var onOpenPath: ((String) -> Void)? = nil
    var onSelectAnswer: ((String) -> Void)? = nil
    var onSubmitAnswer: ((String) -> Void)? = nil

    @State private var thoughtExpanded = false
    @State private var expandedToolIDs: Set<String> = []
    @State private var now = Date()

    private var content: AgentTurnContent {
        AgentTurnContent.partition(parts: parts)
    }

    private var isRunning: Bool {
        AgentTurnContent.isRunning(parts)
    }

    private var totalSeconds: TimeInterval {
        AgentTurnContent.spanSeconds(for: parts, now: now, isRunning: isRunning)
    }

    private var thoughtSeconds: TimeInterval {
        AgentTurnContent.thoughtSeconds(
            parts: parts,
            thoughtText: content.thought,
            totalSeconds: totalSeconds,
            now: now,
            isRunning: isRunning
        )
    }

    private var thoughtLabel: String {
        if content.thought.isEmpty { return "" }
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
            if !content.thought.isEmpty {
                thoughtSection
            }

            if !content.tools.isEmpty {
                toolsSection
            }

            if !content.questions.isEmpty {
                questionsSection
            }

            answerSection

            footerRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { date in
            if isRunning { now = date }
        }
        .contextMenu { contextMenuItems }
    }

    // MARK: - Sections

    private var thoughtSection: some View {
        DisclosureGroup(isExpanded: $thoughtExpanded) {
            Text(content.thought)
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

    @ViewBuilder
    private var toolsSection: some View {
        let displayTools = content.tools.filter { $0.kind != .askQuestion }
        if !displayTools.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(displayTools) { action in
                    AgentToolRow(
                        action: action,
                        isExpanded: expandedToolIDs.contains(action.id),
                        onToggle: {
                            if expandedToolIDs.contains(action.id) {
                                expandedToolIDs.remove(action.id)
                            } else {
                                expandedToolIDs.insert(action.id)
                            }
                        },
                        onOpenPath: onOpenPath
                    )
                }
            }
            .padding(.vertical, 2)
            .onChange(of: content.tools.map(\.id).joined(separator: "|")) { _, _ in
                autoExpandFileTools()
            }
            .onAppear {
                autoExpandFileTools()
            }
        }
    }

    private var questionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(content.questions) { question in
                AgentQuestionCard(
                    question: question,
                    onSelectOption: onSelectAnswer,
                    onSubmitAnswer: onSubmitAnswer
                )
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var answerSection: some View {
        if !content.answer.isEmpty {
            AgentMarkdownView(source: content.answer, onOpenPath: onOpenPath)
        } else if isRunning, content.thought.isEmpty, content.tools.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Working…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if content.answer.isEmpty, !isRunning, content.thought.isEmpty, content.tools.isEmpty {
            let fallback = parts.last?.message ?? ""
            if !fallback.isEmpty, !AgentChatFormatting.looksLikeRawToolNoise(fallback) {
                AgentMarkdownView(source: fallback, onOpenPath: onOpenPath)
            }
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(workedLabel)
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            if showDone, !isRunning {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                    Text("DONE")
                        .font(.caption2.weight(.bold).monospaced())
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.green.opacity(0.12), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Done")
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        if !content.answer.isEmpty {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = content.answer
                #endif
            } label: {
                Label("Copy answer", systemImage: "doc.on.doc")
            }
        }
        if !content.thought.isEmpty {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = content.thought
                #endif
            } label: {
                Label("Copy thought", systemImage: "brain")
            }
        }
    }

    private func autoExpandFileTools() {
        for action in content.tools where action.hasExpandableBody {
            if action.kind == .edit || action.kind == .write {
                expandedToolIDs.insert(action.id)
            }
        }
    }
}
