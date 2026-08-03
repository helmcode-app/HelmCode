//
//  AgentTimelineNodes.swift
//  HelmCode
//
//  Timeline row, stage badge, and terminal result card for AgentTimelineView.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Timeline node

struct AgentTimelineNode: View {
    let entry: EventLog
    var isLast: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                AgentStageBadge(kind: entry.badgeKind, stage: entry.stage)
                    .frame(width: 28, height: 28)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.stageLabel)
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(badgeColor)
                    if let cycle = entry.cycle {
                        Text("C\(cycle)")
                            .font(.caption2.monospaced().weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(badgeColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor)
                    }
                    Spacer(minLength: 0)
                    Text(timeLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    Text(entry.logBody)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(.secondarySystemBackground).opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.04), lineWidth: 1)
                )
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .padding(.bottom, isLast ? 4 : 14)
        }
        .padding(.leading, 12)
    }

    private var timeLabel: String {
        let d = entry.timestamp
        guard d != .distantPast else { return entry.at }
        return d.formatted(date: .omitted, time: .standard)
    }

    private var badgeColor: Color {
        AgentStageBadge.color(for: entry.badgeKind)
    }
}

// MARK: - Stage badge

struct AgentStageBadge: View {
    let kind: AgentTimelineBadgeKind
    var stage: AgentEventStage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Self.color(for: kind).opacity(kind == .success ? 0.22 : 0.16))
                .overlay(
                    Circle()
                        .strokeBorder(Self.color(for: kind).opacity(0.55), lineWidth: 1.2)
                )
                .shadow(
                    color: kind == .success ? Color.green.opacity(0.45) : .clear,
                    radius: kind == .success ? 5 : 0
                )

            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Self.color(for: kind))
        }
        .accessibilityLabel(stage?.displayName ?? kindAccessibility)
    }

    private var symbolName: String {
        switch kind {
        case .user: return "person.fill"
        case .provisioning: return "circle.fill"
        case .warning: return "exclamationmark"
        case .success: return "checkmark"
        case .cancelled: return "minus"
        case .neutral: return "circle"
        }
    }

    private var kindAccessibility: String {
        switch kind {
        case .user: return "You"
        case .provisioning: return "Provisioning"
        case .warning: return "Warning"
        case .success: return "Success"
        case .cancelled: return "Cancelled"
        case .neutral: return "Event"
        }
    }

    static func color(for kind: AgentTimelineBadgeKind) -> Color {
        switch kind {
        case .user: return .accentColor
        case .provisioning: return Color(red: 0.95, green: 0.68, blue: 0.12)
        case .warning: return Color(red: 0.95, green: 0.28, blue: 0.25)
        case .success: return Color(red: 0.22, green: 0.78, blue: 0.42)
        case .cancelled: return .orange
        case .neutral: return .secondary
        }
    }
}

// MARK: - Result card

struct AgentResultCard: View {
    let result: AgentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: result.status == .succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundStyle(result.status == .succeeded ? Color.green : .red)
                Text(result.status.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result.status == .succeeded ? Color.green : .red)
                Spacer(minLength: 0)
                Text("\(result.durationMs) ms")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Text(result.summary)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    metaChip(icon: "arrow.branch", text: result.branch)
                    if let sha = result.commitSha {
                        metaChip(icon: "number", text: String(sha.prefix(12)))
                    }
                    metaChip(icon: "checkmark.diamond", text: "tests \(result.testAttempts.count)")
                }
            }

            if let error = result.error, !error.isEmpty {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(error)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    (result.status == .succeeded ? Color.green : Color.red).opacity(0.25),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func metaChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .labelStyle(.titleAndIcon)
    }
}
