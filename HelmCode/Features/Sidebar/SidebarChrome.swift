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

// MARK: - VFS status (sidebar top trailing, with system collapse)

/// Global VFS connection glyph for the sidebar **system** toolbar (top trailing).
/// Shown only when a project is open (`SidebarView` gates placement).
/// Independent of per-project list trailing icons (`ProjectRunnerStatusIcon`).
struct SidebarVFSStatusIcon: View {
    @ObservedObject var vfs: VFSNetworkEngine

    var body: some View {
        let state = vfs.connectionState
        Label(state.shortTitle, systemImage: state.toolbarSystemImage)
            .labelStyle(.iconOnly)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(state.toolbarTint)
            .accessibilityLabel(state.shortTitle)
            .help(helpText)
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
/// Uses a sidebar `List` so leading inset / body metrics match navigator lists.
/// Scroll background is hidden so the bar material and edge fade remain visible.
struct SidebarSettingsBar: View {
    var action: () -> Void

    var body: some View {
        List {
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
            }
            .buttonStyle(.plain)
            .listItemTint(.primary)
            .accessibilityHint("Opens app settings")
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .frame(maxHeight: 52)
    }
}
