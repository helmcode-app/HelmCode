//
//  InspectorToggleButton.swift
//  HelmCode
//
//  Plain toolbar icon button. Must be placed in a *system* toolbar
//  (NavigationSplitView detail / NavigationStack) — never restyle with .bordered.
//

import SwiftUI

struct InspectorToggleButton: View {
    var isExpanded: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
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
