//
//  AgentProcessingBanner.swift
//  HelmCode
//
//  Legacy working strip — Stop now lives on the composer send button.
//  Kept as a slim status caption for optional reuse above the dock.
//

import SwiftUI

struct AgentProcessingBanner: View {
    @ObservedObject var agent: AgentNetworkEngine

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
            Text(statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusLabel)
    }

    private var statusLabel: String {
        if agent.composerMode == .ask {
            return "Thinking…"
        }
        if let poll = agent.pollStatus?.displayName, !poll.isEmpty {
            return poll
        }
        return "Working…"
    }
}
