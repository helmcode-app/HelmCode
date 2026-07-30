//
//  SidebarChrome.swift
//  HelmCode
//
//  Shared sidebar chrome: list style, scroll-edge fade, system bottom settings bar.
//

import SwiftUI

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
