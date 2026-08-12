//
//  AgentProcessingBanner.swift
//  HelmCode
//
//  Compact “agent is working” strip above the composer.
//

import SwiftUI

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
        .background(
            Color.accentColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}
