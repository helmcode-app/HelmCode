//
//  AgentCommandHeader.swift
//  HelmCode
//
//  Cursor-like agent chat header: session title, phase chip, new/stop.
//

import SwiftUI

struct AgentCommandHeader: View {
    @ObservedObject var agent: AgentNetworkEngine
    var showActions: Bool
    var onOpenSessions: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if showActions {
                sessionButton
                Spacer(minLength: 4)
                phaseChip
                trailingAction
            } else {
                Text("Agent")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("UNAVAILABLE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground).opacity(0.55))
    }

    // MARK: - Pieces

    private var sessionButton: some View {
        Button(action: onOpenSessions) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.caption.weight(.semibold))
                Text(headerTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!agent.socketState.isReady)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if agent.phase.isBusy {
            Button {
                Task { await agent.cancelActiveTask() }
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop")
        } else {
            Button {
                Task { await agent.startNewChat() }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New chat")
            .disabled(!agent.socketState.isReady)
        }
    }

    private var headerTitle: String {
        if agent.activeSessionID == nil, SessionChatTitle.isPlaceholder(agent.sessionTitle) {
            return "Agent"
        }
        return SessionChatTitle.display(agent.sessionTitle)
    }

    private var phaseChip: some View {
        Text(agent.phase.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(agent.phase.tintColor.opacity(0.16), in: Capsule())
            .foregroundStyle(agent.phase.tintColor)
    }
}

// MARK: - Phase tint

extension AgentControllerPhase {
    var tintColor: Color {
        switch self {
        case .idle, .ready: return .secondary
        case .connecting: return .orange
        case .launching, .processing: return .accentColor
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}
