//
//  AgentTimelineView.swift
//  HelmCode
//
//  Cursor-style chat transcript: user bubbles + grouped agent turn cards.
//  Restore checkpoint only on user messages.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentTimelineView: View {
    @ObservedObject var agent: AgentNetworkEngine
    @State private var confirmRevertId: String?

    private var transcript: [AgentTranscriptItem] {
        AgentTranscriptItem.build(from: agent.eventLog)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if transcript.isEmpty {
                        emptyState
                            .transition(.opacity)
                    } else {
                        ForEach(transcript) { item in
                            switch item {
                            case .user(let entry):
                                AgentUserBubble(
                                    entry: entry,
                                    onRevert: userMessageId(for: entry).map { mid in
                                        { confirmRevertId = mid }
                                    }
                                )
                                .id(item.id)
                            case .agentTurn(_, let parts):
                                AgentTurnCard(parts: parts)
                                    .id(item.id)
                            }
                        }
                    }

                    if let err = agent.lastError, agent.result == nil, !agent.phase.isBusy {
                        errorBanner(err)
                            .id("error-banner")
                    }

                    if agent.phase == .succeeded {
                        doneFooter
                            .id("done-footer")
                    }

                    Color.clear.frame(height: 8).id("chat-bottom")
                }
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.2), value: agent.eventLog.count)
                .animation(.easeOut(duration: 0.2), value: agent.phase.label)
            }
            .scrollIndicators(.automatic)
            .onChange(of: agent.eventLog.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: agent.eventLog.last?.message) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: agent.phase.label) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .confirmationDialog(
                "Restore checkpoint?",
                isPresented: Binding(
                    get: { confirmRevertId != nil },
                    set: { if !$0 { confirmRevertId = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    if let mid = confirmRevertId {
                        Task { await agent.revertToMessage(messageId: mid) }
                    }
                    confirmRevertId = nil
                }
                Button("Cancel", role: .cancel) {
                    confirmRevertId = nil
                }
            } message: {
                Text("Removes this message and everything after, undoes file changes, and puts the text back in the input. You can undo the restore once.")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Start a conversation")
                .font(.headline)
            Text("Ask a question, plan a change, or let the agent edit the project — like Cursor chat.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }

    private var doneFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Done")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if agent.canUnrevert {
                Button("Undo restore") {
                    Task { await agent.unrevertLast() }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
    }

    /// Restore only for user-authored messages with a real OpenCode id.
    private func userMessageId(for entry: EventLog) -> String? {
        guard entry.stage == .userCommand else { return nil }
        guard let mid = entry.detail?["timelineId"]?.stringValue, mid.hasPrefix("msg") else {
            return nil
        }
        return mid
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }
}

#Preview {
    AgentTimelineView(agent: AgentNetworkEngine())
        .frame(width: 360, height: 640)
}
