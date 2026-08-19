//
//  AgentComposerUsageMeter.swift
//  HelmCode
//
//  Composer context-window + cost. Narrow inspector hides the dollar amount first.
//

import SwiftUI

struct AgentComposerUsageMeter: View {
    let usage: SessionUsage?

    var body: some View {
        let fraction = usage?.fraction ?? 0
        let tint = Self.tint(fraction)
        return ViewThatFits(in: .horizontal) {
            cluster(fraction: fraction, tint: tint, showCost: true)
            cluster(fraction: fraction, tint: tint, showCost: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }

    private func cluster(fraction: Double, tint: Color, showCost: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: Self.gaugeSymbol(fraction))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
            Text(usage?.contextLabel ?? "—")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if showCost, let cost = usage?.costLabel {
                Text(cost)
                    .font(.caption.weight(.regular).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var accessibilityLabel: String {
        guard let usage else { return "Context size unavailable" }
        var parts = ["Context \(usage.contextLabel)"]
        if let cost = usage.costLabel {
            parts.append("Cost \(cost)")
        }
        return parts.joined(separator: ", ")
    }

    private var help: String {
        guard let usage else {
            return "Context window and cost appear when the agent reports usage"
        }
        if let cost = usage.costLabel {
            return "Context \(usage.contextLabel) · \(cost)"
        }
        return "Context \(usage.contextLabel)"
    }

    private static func gaugeSymbol(_ fraction: Double) -> String {
        if fraction >= 0.95 { return "gauge.with.dots.needle.bottom.100percent" }
        if fraction >= 0.67 { return "gauge.with.dots.needle.67percent" }
        if fraction >= 0.33 { return "gauge.with.dots.needle.bottom.50percent" }
        return "gauge.with.dots.needle.33percent"
    }

    private static func tint(_ fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.75 { return .orange }
        return .secondary
    }
}
