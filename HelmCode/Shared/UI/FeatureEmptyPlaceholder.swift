//
//  FeatureEmptyPlaceholder.swift
//  HelmCode
//
//  Icon + title + subtitle for column-level empty states
//  (Commander unavailable, future surfaces).
//  Sidebar text-only empty uses `SidebarEmptyPlaceholder`.
//

import SwiftUI

struct FeatureEmptyPlaceholder: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var imageSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 24)
            Image(systemName: systemImage)
                .font(.system(size: imageSize))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FeatureEmptyPlaceholder(
        systemImage: "bolt.horizontal.circle",
        title: "Open a project to use the agent",
        subtitle: "Open a project first, then chat with the agent here."
    )
}
