//
//  CommanderTimelineViews.swift
//  HelmCode
//
//  Timeline rows for Commander streaming events + terminal result banner.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CommanderEventRow: View {
    let event: TaskProgressEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(event.status.displayName.uppercased())
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(statusColor)
                    Text(timeLabel)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                Text(event.message)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                if let detail = detailSummary {
                    Text(detail)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground).opacity(0.25))
    }

    private var timeLabel: String {
        let d = event.timestamp
        guard d != .distantPast else { return event.at }
        return d.formatted(date: .omitted, time: .standard)
    }

    private var detailSummary: String? {
        guard let detail = event.detail, !detail.isEmpty else { return nil }
        let parts = detail.compactMap { key, value -> String? in
            guard let s = value.stringValue else { return "\(key)" }
            return "\(key)=\(s)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch event.status {
        case .queued: return .gray
        case .running: return .blue
        case .testing: return .cyan
        case .healing: return .orange
        case .committing, .pushing: return .purple
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

struct CommanderResultBanner: View {
    let result: AgentResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                result.status.displayName,
                systemImage: result.status == .succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(result.status == .succeeded ? Color.green : .red)

            Text(result.summary)
                .font(.caption)
                .textSelection(.enabled)

            if let sha = result.commitSha {
                Text("\(result.branch) @ \(sha.prefix(12))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(result.branch)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Text("duration \(result.durationMs) ms · tests \(result.testAttempts.count)")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let error = result.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
