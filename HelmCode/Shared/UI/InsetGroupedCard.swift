//
//  InsetGroupedCard.swift
//  HelmCode
//
//  Shared card chrome for welcome / empty-state lists.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Uppercase section label used on welcome / empty pages.
struct SectionCaption: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

/// Rounded secondary-background card wrapping a vertical stack of rows.
struct InsetGroupedCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

/// Leading icon + title/subtitle + optional chevron row used in welcome cards.
struct WelcomeListRow: View {
    let title: String
    var subtitle: String? = nil
    var subtitleMonospaced: Bool = false
    let systemImage: String
    var isEnabled: Bool = true
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(subtitleMonospaced ? .caption.monospaced() : .caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if showsChevron && isEnabled {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
