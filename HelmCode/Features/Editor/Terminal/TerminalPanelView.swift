//
//  TerminalPanelView.swift
//  HelmCode
//
//  Full-column WebSSH terminal (exclusive with the code editor in the center column).
//  Background matches the editor column (`Color(.systemBackground)`) in light & dark.
//

import SwiftUI

struct TerminalPanelView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine
    @Binding var isPresented: Bool

    @Environment(\.colorScheme) private var colorScheme

    @State private var statusText = "disconnected"
    @State private var statusKind: TerminalLinkStatus = .info
    @State private var reconnectGeneration: UInt64 = 0

    private var runnerURL: String {
        RunnerURL.httpBase(from: engine.baseURLString, fallback: RunnerConnectionPrefs.defaultURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            TerminalHostView(
                baseURLString: runnerURL,
                apiToken: engine.apiToken,
                isDark: colorScheme == .dark,
                reconnectGeneration: reconnectGeneration,
                isActive: isPresented,
                onStatus: { text, kind in
                    statusText = text
                    statusKind = kind
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(.systemBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
    }

    // MARK: - Chrome

    private var chromeBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Terminal")
                .font(.caption.weight(.semibold))
            Text("bash")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            Text(statusText)
                .font(.caption2.monospaced())
                .foregroundStyle(statusKind.foreground)
                .lineLimit(1)

            Button {
                reconnectGeneration &+= 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Reconnect terminal")

            Button {
                withAnimation(LayoutMetrics.panelSlideAnimation) {
                    isPresented = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Show editor")
            .help("Back to editor")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
