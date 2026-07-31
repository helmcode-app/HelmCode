//
//  SystemChrome.swift
//  HelmCode
//
//  Shared iOS system control chrome (segmented pickers, sheet dismiss).
//

import SwiftUI

extension View {
    /// Large iOS `UISegmentedControl` styling used by sidebar navigator + Open Project tabs.
    func helmLargeSegmentedStyle() -> some View {
        pickerStyle(.segmented)
            .controlSize(.large)
            .tint(Color.accentColor)
    }

    /// Leading toolbar close control (xmark) for sheets.
    func helmSheetCloseToolbar(disabled: Bool = false, action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: action) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
                .disabled(disabled)
            }
        }
    }
}
