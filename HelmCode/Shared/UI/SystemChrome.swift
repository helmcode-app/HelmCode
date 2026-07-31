//
//  SystemChrome.swift
//  HelmCode
//
//  Shared iOS system control chrome (segmented pickers, sheet dismiss, form fields).
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

    /// Settings / Open Project URL fields — no auto-cap, no correct, URL keyboard.
    func helmURLFieldStyle() -> some View {
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .textContentType(.URL)
    }

    /// Backend token / monospaced config fields.
    func helmMonospacedFieldStyle() -> some View {
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(.body.monospaced())
    }
}

extension VFSConnectionState {
    /// Secondary when ready; orange while connecting / offline / error.
    var statusForeground: Color {
        isReady ? Color.secondary : Color.orange
    }
}
