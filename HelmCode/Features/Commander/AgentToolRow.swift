//
//  AgentToolRow.swift
//  HelmCode
//
//  One tool invocation row (pi / Grok harness style) + processing banner.
//

import SwiftUI

/// ```
/// ◆ Read  path/to/File.swift
/// ◇ Read  path/to/File.swift
///   42 lines
///   …body when expanded…
/// ```
struct AgentToolRow: View {
    let action: AgentToolAction
    var isExpanded: Bool
    var onToggle: () -> Void
    /// Open the tool's file path in the editor when available.
    var onOpenPath: ((String) -> Void)? = nil

    private let maxPreviewLines = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Do not use Button.disabled — it greys the whole row.
            header
                .contentShape(Rectangle())
                .onTapGesture {
                    guard action.hasExpandableBody else {
                        if let path = action.path, !path.isEmpty {
                            onOpenPath?(path)
                        }
                        return
                    }
                    onToggle()
                }
                .accessibilityAddTraits(action.hasExpandableBody ? .isButton : [])
                .accessibilityLabel("\(action.verb) \(action.detail)")

            if let stats = action.statsLabel {
                Text(stats)
                    .font(.caption2.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
            } else if action.statusKind == .running {
                Text(runningHint)
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.9))
                    .padding(.leading, 20)
            }

            if isExpanded, action.hasExpandableBody {
                toolBody
                    .padding(.leading, 20)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if action.statusKind == .running {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 12)
            } else {
                Text(statusGlyph)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .frame(width: 14, alignment: .center)
            }

            Text(action.verb)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            if let path = action.path, !path.isEmpty, onOpenPath != nil {
                Button {
                    onOpenPath?(path)
                } label: {
                    Text(action.detail)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(path)")
            } else {
                Text(action.detail)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 4)

            if action.hasExpandableBody {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var runningHint: String {
        switch action.kind {
        case .read: return "Reading…"
        case .write: return "Writing…"
        case .edit: return "Editing…"
        case .run: return "Running…"
        case .search: return "Searching…"
        case .list: return "Listing…"
        case .askQuestion: return "Asking…"
        case .other: return "Working…"
        }
    }

    private var statusGlyph: String {
        switch action.statusKind {
        case .ok: return "◇"
        case .running: return "◆"
        case .error: return "✗"
        }
    }

    private var statusColor: Color {
        switch action.statusKind {
        case .ok: return .green.opacity(0.9)
        case .running: return .orange
        case .error: return .red
        }
    }

    @ViewBuilder
    private var toolBody: some View {
        let lines = Array(action.contentLines.prefix(maxPreviewLines))
        let overflow = max(0, action.contentLines.count - maxPreviewLines)

        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(diffStyle(for: line))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if overflow > 0 {
                Text("… \(overflow) more")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func diffStyle(for line: String) -> AnyShapeStyle {
        guard action.diffStats != nil else { return AnyShapeStyle(.secondary) }
        if line.hasPrefix("+++") || line.hasPrefix("---") {
            return AnyShapeStyle(.tertiary)
        }
        if line.hasPrefix("+") { return AnyShapeStyle(Color.green) }
        if line.hasPrefix("-") { return AnyShapeStyle(Color.red) }
        return AnyShapeStyle(.secondary)
    }
}


