//
//  AgentCommandHeader.swift
//  HelmCode
//
//  System navigation bar toolbar items for the Agent inspector column.
//

import SwiftUI

struct AgentCommandToolbar: ToolbarContent {
    @ObservedObject var agent: AgentNetworkEngine
    var showActions: Bool
    var onOpenSessions: () -> Void

    var body: some ToolbarContent {
        if showActions {
            ToolbarItem(placement: .topBarLeading) {
                sessionButton
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    statusChip
                    newChatButton
                }
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                Text("Agent")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .topBarTrailing) {
                Text("UNAVAILABLE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    // MARK: - Pieces

    private var sessionButton: some View {
        Button(action: onOpenSessions) {
            HStack(spacing: 6) {
                Text("Chats")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)

                Text(chatTitle)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
            }
            // Cap width so the session title truncates instead of shoving the trailing tools.
            .frame(maxWidth: 220, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(!agent.socketState.isReady)
        .accessibilityLabel("Chats, \(chatTitle)")
    }

    private var newChatButton: some View {
        Button {
            Task { await agent.startNewChat() }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New chat")
        .disabled(!agent.socketState.isReady || agent.phase.isBusy)
    }

    private var chatTitle: String {
        if agent.activeSessionID == nil, SessionChatTitle.isPlaceholder(agent.sessionTitle) {
            return "New chat"
        }
        return SessionChatTitle.display(agent.sessionTitle)
    }

    /// Only surface exceptional / in-flight chrome — idle success stays quiet like Cursor/Claude.
    @ViewBuilder
    private var statusChip: some View {
        switch agent.phase {
        case .connecting:
            phaseCapsule(label: "CONNECTING", tint: .orange)
        case .launching, .processing:
            phaseCapsule(label: agent.phase.label.uppercased(), tint: .accentColor)
        case .failed:
            phaseCapsule(label: "FAILED", tint: .red)
        case .cancelled:
            phaseCapsule(label: "STOPPED", tint: .orange)
        case .idle, .ready, .succeeded:
            EmptyView()
        }
    }

    private func phaseCapsule(label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.bold).monospaced())
            .tracking(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint)
            .symbolEffect(.pulse, isActive: agent.phase.isBusy || agent.phase.isLinking)
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
