//
//  AgentTimelineView.swift
//  HelmCode
//
//  Cursor-style chat transcript: user bubbles + grouped agent turn cards.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentTimelineView: View {
    @ObservedObject var agent: AgentNetworkEngine

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
                        let lastAgentTurnID = transcript.last(where: {
                            if case .agentTurn = $0 { return true }
                            return false
                        })?.id

                        ForEach(transcript) { item in
                            switch item {
                            case .user(let entry):
                                AgentUserBubble(
                                    entry: entry,
                                    onConfirmRewind: agent.phase.isBusy
                                        ? nil
                                        : { mid in
                                            Task { await agent.rewindToMessage(mid) }
                                        }
                                )
                                .id(item.id)
                            case .agentTurn(_, let parts):
                                // Done only on the latest agent turn after the current task succeeds.
                                let isLatestTurn = item.id == lastAgentTurnID
                                AgentTurnCard(
                                    parts: parts,
                                    showDone: isLatestTurn && agent.phase == .succeeded
                                )
                                .id(item.id)
                            }
                        }
                    }

                    if let err = agent.lastError, agent.result == nil, !agent.phase.isBusy {
                        errorBanner(err)
                            .id("error-banner")
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
