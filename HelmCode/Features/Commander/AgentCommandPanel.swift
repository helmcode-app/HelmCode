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
        NavigationStack {
            Group {
                if projectRunnerReady {
                    activeWorkspaceBody
                } else {
                    unavailableBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar(removing: .title)
            .toolbar {
                AgentCommandToolbar(
                    agent: agent,
                    showActions: projectRunnerReady,
                    onOpenSessions: { showSessionPicker = true }
                )
            }
        }
        .onChange(of: session.selectedProjectID) { _, _ in
            seedBranchFromProject()
            agent.clearContextPaths()
        }
        .onChange(of: session.sourceControl?.branch) { _, _ in
            seedBranchFromProject()
        }
        .sheet(isPresented: $showSessionPicker) {
            AgentSessionPickerSheet(agent: agent)
        }
    }

    // MARK: - Layouts

    private var unavailableBody: some View {
        FeatureEmptyPlaceholder(
            systemImage: "bubble.left.and.bubble.right",
            title: Copy.unavailableTitle,
            subtitle: Copy.unavailableSubtitle
        )
    }

    private var activeWorkspaceBody: some View {
        AgentTimelineView(agent: agent, onOpenPath: openPathInEditor)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                composerDock
            }
            .onAppear {
                seedBranchFromProject()
            }
    }

    private func openPathInEditor(_ path: String) {
        guard let project = session.selectedProject,
              let node = project.root.find(path: path),
              !node.isDirectory
        else { return }
        session.openFile(node.id)
    }

    private var composerDock: some View {
        AgentCommandComposer(
            agent: agent,
            session: session,
            promptFocused: $promptFocused,
            promptSelection: $promptSelection,
            isLaunching: $isLaunching,
            canLaunch: canLaunch,
            onSend: { Task { await launch() } }
        )
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
            guard agent.phase != .cancelled else { return }
            promptSelection = nil
            promptFocused = false
            await agent.refreshSessionList()
        } catch {
            // phase / lastError already set on the engine — keep prompt for retry.
        }
    }

    private func seedBranchFromProject() {
        let live = AgentComposerBranches.currentName(
            sourceControlBranch: session.sourceControl?.branch,
            projectBranch: session.selectedProject?.trimmedBranch,
            fallback: ""
        )
        if live != "branch" {
            agent.baseBranch = live
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
