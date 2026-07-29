//
//  SidebarNavigatorTabBar.swift
//  HelmCode
//
//  System segmented control only — no custom divider drawing.
//  (iOS UISegmentedControl does not ship Xcode/AppKit-style short
//  inter-segment separators; those would require hand-drawn images.)
//

import SwiftUI

struct SidebarNavigatorTabBar: View {
    @Binding var selection: SidebarNavigator
    var badges: [SidebarNavigator: Int] = [:]

    var body: some View {
        Picker("Navigator", selection: $selection) {
            ForEach(SidebarNavigator.allCases) { nav in
                Image(systemName: nav.systemImage)
                    .tag(nav)
                    .accessibilityLabel(accessibilityLabel(for: nav))
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        // Selected segment / glyph follows the app tint (list selection blue).
        .tint(Color.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func accessibilityLabel(for nav: SidebarNavigator) -> String {
        if let badge = badges[nav], badge > 0 {
            return "\(nav.title), \(badge)"
        }
        return nav.title
    }
}
