//
//  AgentCommandPanel.swift
//  HelmCode
//
//  Cursor-style agent chat: session switcher + transcript + composer.
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
    @State private var showSessionPicker = false

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
        .sheet(isPresented: $showSessionPicker) {
            AgentSessionPickerSheet(agent: agent)
        }
    }

    // MARK: - No project

    private var unavailableBody: some View {
        VStack(spacing: 0) {
            headerBar(showActions: false)
            Divider().opacity(0.5)
            FeatureEmptyPlaceholder(
                systemImage: "bubble.left.and.bubble.right",
                title: Copy.unavailableTitle,
                subtitle: Copy.unavailableSubtitle
            )
        }
    }

    // MARK: - Project open

    private var activeWorkspaceBody: some View {
        VStack(spacing: 0) {
            headerBar(showActions: true)
            Divider().opacity(0.35)
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

    // MARK: - Header (Cursor-like)

    private func headerBar(showActions: Bool) -> some View {
        HStack(spacing: 8) {
            if showActions {
                Button {
                    showSessionPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.caption.weight(.semibold))
                        Text(headerTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!agent.socketState.isReady)

                Spacer(minLength: 4)

                phaseChip

                if agent.canUnrevert, !agent.phase.isBusy {
                    Button {
                        Task { await agent.unrevertLast() }
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Undo restore")
                    .help("Undo last checkpoint restore")
                }

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
                    .accessibilityLabel("Stop")
                } else {
                    Button {
                        Task { await agent.startNewChat() }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New chat")
                    .disabled(!agent.socketState.isReady)
                }
            } else {
                Text("Agent")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
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

    private var headerTitle: String {
        if let t = agent.sessionTitle, !t.isEmpty { return t }
        if agent.activeSessionID != nil { return "Chat" }
        return "Agent"
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
            await agent.refreshSessionList()
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

    private enum Copy {
        static let unavailableTitle = "Open a project to chat"
        static let unavailableSubtitle = "Open a project first, then use Agent like Cursor chat."
    }
}

// MARK: - Phase tint (UI)

extension AgentControllerPhase {
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
