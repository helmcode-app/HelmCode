//
//  AgentUserBubble.swift
//  HelmCode
//
//  User chat bubble: content on top; time + Restore on the bottom row.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentUserBubble: View {
    let entry: EventLog
    /// Called after the user confirms restore (message id already validated).
    var onConfirmRevert: ((String) -> Void)?

    @State private var showRestoreConfirm = false

    private var messageId: String? {
        guard let mid = entry.detail?["timelineId"]?.stringValue, mid.hasPrefix("msg") else {
            return nil
        }
        return mid
    }

    private var canShowRevert: Bool {
        messageId != nil && onConfirmRevert != nil
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
                    if canShowRevert {
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
                        .accessibilityLabel("Restore checkpoint")
                        .help("Restore: remove this message and after, put text back in the composer")
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
                "Restore checkpoint?",
                isPresented: $showRestoreConfirm,
                titleVisibility: .visible
            ) {
                Button("Restore", role: .destructive) {
                    if let mid = messageId {
                        onConfirmRevert?(mid)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes this message and everything after, undoes file changes, and puts the text back in the input.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .contextMenu {
            if canShowRevert {
                Button(role: .destructive) {
                    showRestoreConfirm = true
                } label: {
                    Label("Restore to this message", systemImage: "arrow.uturn.backward.circle")
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
