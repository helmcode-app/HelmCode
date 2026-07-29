//
//  InspectorToggleButton.swift
//  HelmCode
//
//  Trailing Commander show/hide control. Rendered as a plain toolbar Button so
//  NavigationSplitView applies the same chrome/size as the system sidebarToggle
//  (do not restyle with .bordered / .buttonBorderShape — that diverges from system).
//

import SwiftUI

struct InspectorToggleButton: View {
    var isExpanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            // Icon-only Label matches how system toolbar items are declared.
            Label(
                isExpanded ? "Hide Commander" : "Show Commander",
                systemImage: "sidebar.right"
            )
            .labelStyle(.iconOnly)
        }
        .accessibilityLabel(isExpanded ? "Hide Commander" : "Show Commander")
        .accessibilityValue(isExpanded ? "Visible" : "Hidden")
    }
}
