//
//  AgentChrome.swift
//  HelmCode
//
//  Industrial IDE tokens for the Agent inspector — hairlines, tracked labels,
//  tight radii. Stays inside system materials (no custom glass rims).
//

import SwiftUI

enum AgentChrome {
    /// Composer glass corner — slightly tighter than the old soft 26.
    static let composerRadius: CGFloat = 22
    /// Prompt / turn cards.
    static let cardRadius: CGFloat = 10
    /// Code fences & tool bodies.
    static let codeRadius: CGFloat = 8
    /// Chip / pill controls.
    static let chipRadius: CGFloat = 7

    static let composerInset: CGFloat = 12
    static let timelineGutter: CGFloat = 14

    static let sendStopSize: CGFloat = 34

    static let chipSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
    static let sendMorph = Animation.easeInOut(duration: 0.18)
    static let reveal = Animation.easeOut(duration: 0.22)

    /// Hairline rule used between composer bands and code headers.
    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    /// Quiet fill for user prompt cards (not accent-tinted chat bubbles).
    static var promptFill: Color {
        Color(.secondarySystemFill)
    }

    /// Slightly denser fill for code / tool bodies.
    static var codeFill: Color {
        Color(.tertiarySystemFill)
    }

    /// Industrial index label: `01`, `02`.
    static func indexLabel(_ index: Int) -> String {
        String(format: "%02d", index)
    }
}

/// Leading industrial accent rail for prompt cards and code fences.
struct AgentAccentRail: View {
    var tint: Color = Color.accentColor
    var width: CGFloat = 2

    var body: some View {
        Capsule(style: .continuous)
            .fill(tint.opacity(0.85))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}
