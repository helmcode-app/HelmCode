//
//  AgentUserBubble.swift
//  HelmCode
//
//  User chat bubble: content on top; time + Rewind on the bottom row.
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

    private var timeText: String {
        let d = entry.timestamp
        guard d != .distantPast else { return "" }
        return d.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if !timeText.isEmpty {
                        Text(timeText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    if canShowRewind {
                        Button {
                            showRestoreConfirm = true
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 24, minHeight: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rewind to this message")
                        .help("Rewind: drop this message and after, restore files, put the text back in the composer")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color.accentColor.opacity(0.16),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .confirmationDialog(
                "Rewind to this message?",
                isPresented: $showRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Rewind chat and files", role: .destructive) {
                    if let mid = messageId {
                        onConfirmRewind?(mid)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes this message and everything after, restores the workspace to that checkpoint, and puts the text back in the input. This cannot be undone.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
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
}
