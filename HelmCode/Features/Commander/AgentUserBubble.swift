//
//  AgentUserBubble.swift
//  HelmCode
//
//  Full-width industrial prompt card with a leading accent rail + rewind control.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentUserBubble: View {
    let entry: EventLog
    /// Called after the user confirms rewind (server `user_…` id).
    var onConfirmRewind: ((String) -> Void)?

    @State private var showRestoreConfirm = false

    private var messageId: String? {
        guard let mid = entry.detail?["timelineId"]?.stringValue, !mid.isEmpty else {
            return nil
        }
        return mid
    }

    private var canShowRewind: Bool {
        messageId != nil && onConfirmRewind != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            AgentAccentRail()
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 8) {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10)

                if canShowRewind {
                    rewindButton
                }
            }
            .padding(.trailing, 10)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AgentChrome.promptFill,
            in: RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous))
        .padding(.horizontal, AgentChrome.timelineGutter)
        .padding(.vertical, 5)
        .contextMenu {
            if canShowRewind {
                Button(role: .destructive) {
                    showRestoreConfirm = true
                } label: {
                    Label("Rewind to this message", systemImage: "arrow.uturn.backward.circle")
                }
            }
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = entry.message
                #endif
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    private var rewindButton: some View {
        Button {
            showRestoreConfirm = true
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rewind to this message")
        .help("Rewind: drop this message and after, restore files, put the text back in the composer")
        // Anchor the confirm sheet to this control so it follows the message, not screen center.
        .popover(isPresented: $showRestoreConfirm, arrowEdge: .top) {
            rewindConfirmPopover
                .presentationCompactAdaptation(.popover)
        }
    }

    private var rewindConfirmPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rewind to this message?")
                .font(.subheadline.weight(.semibold))
            Text("Removes this message and everything after, restores the workspace to that checkpoint, and puts the text back in the input. This cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel) {
                    showRestoreConfirm = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Rewind", role: .destructive) {
                    showRestoreConfirm = false
                    if let mid = messageId {
                        onConfirmRewind?(mid)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(width: 280)
    }
}
