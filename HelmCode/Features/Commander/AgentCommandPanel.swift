//
//  AgentCommandPanel.swift
//  HelmCode
//
//  Project-scoped agent command drawer shell:
//  timeline + safe-area composer dock. Composer UI: AgentCommandComposer.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentCommandPanel: View {
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var httpEngine: HelmCodeNetworkEngine

    @FocusState private var promptFocused: Bool
    @State private var isLaunching = false
    @State private var promptSelection: TextSelection?

    private var projectRunnerReady: Bool {
        session.selectedProject?.normalizedRunnerURL != nil
    }

    private var canAddSelectedFile: Bool {
        guard !agent.phase.isBusy,
              agent.socketState.isReady,
              let file = session.selectedFile,
              !file.isDirectory else { return false }
        return true
    }

    private var canLaunch: Bool {
        let trimmed = agent.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return projectRunnerReady
            && !trimmed.isEmpty
            && !agent.phase.isBusy
            && !isLaunching
            && agent.socketState.isReady
            && httpEngine.connectionState.isOnline
    }

    var body: some View {
        Group {
            if projectRunnerReady {
                activeWorkspaceBody
            } else {
                unavailableBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: session.selectedProjectID) { _, _ in
            seedBranchFromProject()
            agent.clearContextPaths()
        }
        .onChange(of: session.selectedFileID) { _, _ in
            seedBranchFromProject()
        }
    }

    // MARK: - No project

    private var unavailableBody: some View {
        VStack(spacing: 0) {
            headerBar(showActions: false)
            Divider().opacity(0.5)

            VStack(spacing: 14) {
                Spacer(minLength: 24)
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Open a project to use the agent")
                    .font(.headline)
                Text(
                    """
                    The headless agent uses the same runner as the open project \
                    (HTTP + VFS + `ws://…/v1/agent`). There is no separate Agent backend.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Project open

    /// Timeline fills the column; composer sits in a bottom safe-area inset so the
    /// session/timeline scroll view always reserves space and never scrolls under it.
    private var activeWorkspaceBody: some View {
        VStack(spacing: 0) {
            headerBar(showActions: true)
            AgentTimelineView(agent: agent)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerDock
        }
        .onAppear {
            seedBranchFromProject()
        }
    }

    private var composerDock: some View {
        VStack(spacing: 8) {
            if agent.phase.isProcessingLayout {
                AgentProcessingBanner(agent: agent)
            }
            AgentCommandComposer(
                agent: agent,
                session: session,
                promptFocused: $promptFocused,
                promptSelection: $promptSelection,
                isLaunching: $isLaunching,
                canLaunch: canLaunch,
                canAddSelectedFile: canAddSelectedFile,
                onSend: { Task { await launch() } }
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Header

    private func headerBar(showActions: Bool) -> some View {
        HStack(spacing: 10) {
            Text("Agent Command")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)

            if showActions {
                phaseChip
                if agent.phase.isBusy {
                    Button {
                        Task { await agent.cancelActiveTask() }
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel agent")
                } else if agent.result != nil || !agent.eventLog.isEmpty {
                    Button {
                        agent.resetSession()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear timeline")
                }
            } else {
                Text("UNAVAILABLE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground).opacity(0.55))
    }

    private var phaseChip: some View {
        Text(agent.phase.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(agent.phase.tintColor.opacity(0.16), in: Capsule())
            .foregroundStyle(agent.phase.tintColor)
    }

    // MARK: - Launch

    private func launch() async {
        isLaunching = true
        defer { isLaunching = false }
        seedBranchFromProject()
        for path in AgentPromptTagging.paths(in: agent.prompt) {
            agent.addContextPath(path)
        }
        do {
            _ = try await agent.launchHeadlessAgent()
            promptSelection = nil
            promptFocused = false
        } catch {
            // phase / lastError already set on the engine — keep prompt for retry.
        }
    }

    private func seedBranchFromProject() {
        if agent.baseBranch == "main" || agent.baseBranch.isEmpty,
           let branch = session.selectedProject?.trimmedBranch,
           !branch.isEmpty {
            agent.baseBranch = branch
        }
    }
}

// MARK: - Phase tint (UI)

extension AgentControllerPhase {
    /// Color for the Agent Command phase chip.
    var tintColor: Color {
        switch self {
        case .idle, .ready: return .secondary
        case .connecting: return .orange
        case .launching, .processing: return .accentColor
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }
}

#Preview("No project") {
    AgentCommandPanel(
        agent: AgentNetworkEngine(),
        session: WorkspaceSession(),
        httpEngine: HelmCodeNetworkEngine()
    )
    .frame(width: 380, height: 720)
}
