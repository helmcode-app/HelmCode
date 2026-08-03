//
//  SystemChrome.swift
//  HelmCode
//
//  Shared iOS system control chrome (segmented pickers, sheet dismiss, form fields).
//  Floating glass uses stock iPadOS 26 Liquid Glass APIs only — no hand-drawn rims.
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

    /**
     Stock iPadOS 26 Liquid Glass panel — **only** system material + interactive bounce.

     Do not layer custom `separator` strokes or multi-shadow stacks on top:
     the system glass compositor already draws the rim + ambient elevation
     (same path as sidebar / toolbar glass). Hand-drawn borders look wrong.
     */
    func helmSystemGlassPanel(
        cornerRadius: CGFloat = 26,
        interactive: Bool = true
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let glass: Glass = interactive ? .regular.interactive() : .regular
        return glassEffect(glass, in: shape)
    }
}

extension VFSConnectionState {
    /// Secondary when ready; orange while connecting / offline / error.
    var statusForeground: Color {
        isReady ? Color.secondary : Color.orange
    }

    /// Sidebar toolbar glyph (global VFS tunnel state).
    var toolbarSystemImage: String {
        switch self {
        case .connected:
            return "externaldrive.connected.to.line.below"
        case .connecting, .reconnecting:
            return "externaldrive.badge.icloud"
        case .failed:
            return "externaldrive.badge.xmark"
        case .disconnected:
            return "externaldrive.badge.minus"
        }
    }

    /// Sidebar toolbar tint for connection health.
    var toolbarTint: Color {
        switch self {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .disconnected:
            return .secondary
        }
    }
}
