//
//  SidebarChrome.swift
//  HelmCode
//
//  Shared sidebar chrome: list style, scroll-edge fade, empty placeholders,
//  and the system bottom settings bar.
//

import SwiftUI

// MARK: - List / edge chrome

extension View {
    /// Sidebar list + soft bottom scroll-edge effect (pairs with `safeAreaBar`).
    func helmSidebarListStyle() -> some View {
        listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    /// System bottom safe-area bar material + soft edge fade for the column.
    func helmSidebarBottomChrome<Bar: View>(@ViewBuilder bar: () -> Bar) -> some View {
        safeAreaBar(edge: .bottom, content: bar)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

// MARK: - Empty navigator

/// Centered title + subtitle for empty Search / Bookmarks / etc. (no icon).
struct SidebarEmptyPlaceholder: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - VFS status (sidebar top trailing, beside system collapse)

/// Global VFS connection glyph. Shown beside the sidebar collapse control
/// only while a project is open. Not a control — no glass, no hit testing.
/// Independent of per-project list trailing icons (`ProjectRunnerStatusIcon`).
struct SidebarVFSStatusIcon: View {
    @ObservedObject var vfs: VFSNetworkEngine

    var body: some View {
        let state = vfs.connectionState
        Image(systemName: state.toolbarSystemImage)
            .font(.body)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(state.toolbarTint)
            .accessibilityLabel(state.shortTitle)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityRemoveTraits(.isButton)
            .help(helpText)
            .allowsHitTesting(false)
    }

    private var helpText: String {
        var parts = [vfs.connectionState.shortTitle]
        if let name = vfs.workspaceName, !name.isEmpty {
            parts.append(name)
        } else if let root = vfs.workspaceRoot, !root.isEmpty {
            parts.append(root)
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Settings bar

/// Settings row in the system bottom safe-area bar.
/// A plain button, not a sidebar `List`: a list in this column joins the split-view
/// selection and makes the navigator tabs flash when the settings sheet opens.
struct SidebarSettingsBar: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Settings")
                    .font(.body)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: "gearshape")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .symbolRenderingMode(.monochrome)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens app settings")
    }
}
