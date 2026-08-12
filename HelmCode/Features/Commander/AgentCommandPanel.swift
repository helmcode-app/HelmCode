//
//  AgentCommandPanel.swift
//  HelmCode
//
//  Cursor-style agent chat: session switcher + transcript + composer.
//

import SwiftUI

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

    // MARK: - Layouts

    private var unavailableBody: some View {
        VStack(spacing: 0) {
            AgentCommandHeader(agent: agent, showActions: false, onOpenSessions: {})
            Divider().opacity(0.5)
            FeatureEmptyPlaceholder(
                systemImage: "bubble.left.and.bubble.right",
                title: Copy.unavailableTitle,
                subtitle: Copy.unavailableSubtitle
            )
        }
    }

    private var activeWorkspaceBody: some View {
        VStack(spacing: 0) {
            AgentCommandHeader(agent: agent, showActions: true) {
                showSessionPicker = true
            }
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

#Preview("No project") {
    AgentCommandPanel(
        agent: AgentNetworkEngine(),
        session: WorkspaceSession(),
        httpEngine: HelmCodeNetworkEngine()
    )
    .frame(width: 380, height: 720)
}
