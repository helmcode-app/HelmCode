//
//  AgentTimelineView.swift
//  HelmCode
//
//  Industrial chat transcript: prompt rails + turn cards + numbered starters.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentTimelineView: View {
    @ObservedObject var agent: AgentNetworkEngine
    var onOpenPath: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var transcript: [AgentTranscriptItem] {
        AgentTranscriptItem.build(from: agent.eventLog)
    }

    private static let starters: [(title: String, subtitle: String, prompt: String)] = [
        (
            "Explain active file",
            "Surface structure, risks, and surprises",
            "Explain the currently open file and call out anything surprising."
        ),
        (
            "Review git changes",
            "Diff critique with concrete fixes",
            "Review the current git changes and suggest concrete improvements."
        ),
        (
            "Fix build errors",
            "Diagnose compile failures end-to-end",
            "Help me diagnose and fix the latest build or compile errors."
        ),
    ]

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
                                let isLatestTurn = item.id == lastAgentTurnID
                                AgentTurnCard(
                                    parts: parts,
                                    showDone: isLatestTurn && agent.phase == .succeeded,
                                    onOpenPath: onOpenPath
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
                .animation(AgentChrome.reveal, value: agent.eventLog.count)
                .animation(AgentChrome.reveal, value: agent.phase.label)
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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AGENT")
                    .font(.caption2.weight(.bold).monospaced())
                    .tracking(1.4)
                    .foregroundStyle(.tertiary)
                Text("Start a conversation")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Ask, plan, or let the agent edit — shortcuts below seed the composer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AgentChrome.timelineGutter)
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(Array(Self.starters.enumerated()), id: \.element.title) { index, starter in
                    if index > 0 {
                        Rectangle()
                            .fill(AgentChrome.hairline(colorScheme))
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                    Button {
                        withAnimation(AgentChrome.chipSpring) {
                            agent.prompt = starter.prompt
                        }
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Text(AgentChrome.indexLabel(index + 1))
                                .font(.caption.weight(.bold).monospaced())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(starter.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(starter.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, AgentChrome.timelineGutter)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(agent.phase.isBusy || !agent.socketState.isReady)
                }
            }
            .background(
                AgentChrome.promptFill,
                in: RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous)
                    .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, AgentChrome.timelineGutter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            AgentAccentRail(tint: .red)
                .padding(.vertical, 2)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .background(
            Color.red.opacity(0.08),
            in: RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous))
        .padding(.horizontal, AgentChrome.timelineGutter)
        .padding(.vertical, 4)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(AgentChrome.reveal) {
            proxy.scrollTo("chat-bottom", anchor: .bottom)
        }
    }
}

#Preview {
    AgentTimelineView(agent: AgentNetworkEngine())
        .frame(width: 360, height: 640)
}
