//
//  AgentTimelineView.swift
//  HelmCode
//
//  DevOps-style real-time streaming timeline bound to AgentNetworkEngine.eventLog.
//  Row / badge / result card: AgentTimelineNodes.swift
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentTimelineView: View {
    @ObservedObject var agent: AgentNetworkEngine

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if agent.eventLog.isEmpty {
                        emptyState
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        ForEach(Array(agent.eventLog.enumerated()), id: \.element.id) { index, entry in
                            AgentTimelineNode(
                                entry: entry,
                                isLast: index == agent.eventLog.count - 1
                            )
                            .id(entry.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                )
                            )
                        }
                    }

                    if agent.phase.isProcessingLayout {
                        processingFooter
                            .id("processing-footer")
                            .padding(.top, 10)
                            .transition(.opacity)
                    }

                    if let result = agent.result {
                        AgentResultCard(result: result)
                            .id("result-banner")
                            .padding(.top, 10)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let err = agent.lastError, agent.result == nil, !agent.phase.isBusy {
                        errorBanner(err)
                            .id("error-banner")
                    }
                }
                .padding(.vertical, 10)
                .animation(.spring(response: 0.38, dampingFraction: 0.86), value: agent.eventLog.count)
                .animation(.easeOut(duration: 0.22), value: agent.phase.label)
            }
            // Bottom safe area comes from the composer dock (`safeAreaInset` on the panel).
            .scrollIndicators(.automatic)
            .onChange(of: agent.eventLog.count) { _, _ in
                scrollToLatest(proxy: proxy)
            }
            .onChange(of: agent.result?.taskId) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("result-banner", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                Image(systemName: "waveform.path.ecg")
                    .font(.title)
                    .foregroundStyle(.tertiary)
            }
            Text("Agent timeline")
                .font(.headline)
            Text("Launch a headless agent to stream provisioning, tests, self-healing, and push events into this console.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var processingFooter: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Agent processing…")
                    .font(.caption.weight(.semibold))
                Text(agent.pollStatus?.displayName ?? agent.phase.label)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.08))
            .padding(.horizontal, 12)
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let last = agent.eventLog.last else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

#Preview {
    let agent = AgentNetworkEngine()
    return AgentTimelineView(agent: agent)
        .frame(width: 360, height: 640)
}
