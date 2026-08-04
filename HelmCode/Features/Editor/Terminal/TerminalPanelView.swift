//
//  TerminalPanelView.swift
//  HelmCode
//
//  Full-column WebSSH chrome for the open project.
//  Kept mounted while the project stays open so ⌘J hide/show preserves the PTY session.
//

import SwiftUI

struct TerminalPanelView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine
    var projectID: String
    var projectRunnerURL: String?
    /// Whether the terminal surface is visible (⌘J).
    var isVisible: Bool
    /// Bumped when the open project changes / closes / shell exits.
    var sessionEpoch: UInt64
    /// Leave Terminal mode after remote `exit`.
    var onSessionEnded: () -> Void
    /// Return to editor without killing the session (x button).
    var onHide: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    @State private var statusText = "disconnected"
    @State private var statusKind: TerminalLinkStatus = .info
    @State private var reconnectGeneration: UInt64 = 0

    private var runnerURL: String {
        TerminalEndpoint.httpBase(
            projectRunnerURL: projectRunnerURL,
            engineBaseURL: engine.baseURLString
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            TerminalHostView(
                baseURLString: runnerURL,
                apiToken: engine.apiToken,
                projectID: projectID,
                isDark: colorScheme == .dark,
                reconnectGeneration: reconnectGeneration,
                sessionEpoch: sessionEpoch,
                isVisible: isVisible && !projectID.isEmpty,
                onStatus: { text, kind in
                    statusText = text
                    statusKind = kind
                },
                onSessionEnded: { _ in onSessionEnded() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(projectID)
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

            Button(action: onHide) {
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

// MARK: - Endpoint helper

enum TerminalEndpoint {
    /// Prefer project runner URL, then engine base, then app default.
    static func httpBase(projectRunnerURL: String?, engineBaseURL: String) -> String {
        let preferred = projectRunnerURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty {
            return RunnerURL.httpBase(from: preferred, fallback: engineBaseURL)
        }
        return RunnerURL.httpBase(
            from: engineBaseURL,
            fallback: RunnerConnectionPrefs.defaultURL
        )
    }
}
