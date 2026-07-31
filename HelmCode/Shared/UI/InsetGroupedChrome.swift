//
//  InsetGroupedChrome.swift
//  HelmCode
//
//  Shared card chrome for welcome / empty-state surfaces.
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

/// Leading inset for dividers that align under icon+title rows.
struct InsetGroupedRowDivider: View {
    var leadingInset: CGFloat = 44

    var body: some View {
        Divider().padding(.leading, leadingInset)
    }
}

/// Leading icon + title/subtitle + optional trailing status + chevron.
struct IconListRow: View {
    let title: String
    var subtitle: String? = nil
    var subtitleMonospaced: Bool = false
    let systemImage: String
    var isEnabled: Bool = true
    var showsChevron: Bool = true
    var runnerStatus: ProjectRunnerReachability? = nil

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

            if let runnerStatus {
                ProjectRunnerStatusIcon(status: runnerStatus)
            }

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

/// Folder icon + name + secondary line + trailing runner status (sidebar / pickers).
struct ProjectListLabel: View {
    let project: WorkspaceProject
    var secondary: ProjectSecondary = .remote
    var runnerStatus: ProjectRunnerReachability = .none

    enum ProjectSecondary {
        case remote
        case branchRemote
    }

    var body: some View {
        HStack(spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                    Text(secondaryText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.accentColor)
            }

            Spacer(minLength: 8)

            ProjectRunnerStatusIcon(status: runnerStatus)
        }
    }

    private var secondaryText: String {
        switch secondary {
        case .remote: return project.remote
        case .branchRemote: return project.branchRemoteLine
        }
    }
}
