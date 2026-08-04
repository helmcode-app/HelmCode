//
//  EditorDetailView.swift
//  HelmCode
//
//  NavigationSplitView detail: welcome → empty project → CodeMirror, or full-column Terminal.
//  Terminal is project-scoped (like Agent). ⌘J toggles visibility; PTY keep-alive until exit / project change.
//

import SwiftUI

struct EditorDetailView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor
    var onOpenSettings: (() -> Void)?

    @AppStorage(AppStorageKey.showCommander) private var showCommander = true
    @AppStorage(AppStorageKey.showTerminal) private var showTerminal = false

    /// Bumped on project switch / close / shell `exit` so Terminal fully resets.
    @State private var terminalSessionEpoch: UInt64 = 0

    private var canUseTerminal: Bool { session.selectedProject != nil }
    private var showingTerminal: Bool { showTerminal && canUseTerminal }

    var body: some View {
        centerColumn
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(LayoutMetrics.panelSlideAnimation, value: showTerminal)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar(removing: .sidebarToggle)
            .toolbar { detailToolbar }
            .background { terminalKeyboardShortcut }
            .onChange(of: session.selectedProjectID) { oldID, newID in
                handleProjectChange(from: oldID, to: newID)
            }
            .onAppear {
                if !canUseTerminal, showTerminal { showTerminal = false }
            }
    }

    // MARK: - Center column (editor ⊕ mounted Terminal)

    /// Terminal stays in the hierarchy (opacity 0) while a project is open so ⌘J
    /// does not destroy WKWebView / WebSocket / scrollback.
    @ViewBuilder
    private var centerColumn: some View {
        ZStack {
            surfaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showingTerminal ? 0 : 1)
                .allowsHitTesting(!showingTerminal)
                .accessibilityHidden(showingTerminal)

            if let project = session.selectedProject {
                TerminalPanelView(
                    engine: engine,
                    projectID: project.id,
                    projectRunnerURL: project.normalizedRunnerURL ?? project.runnerBaseURL,
                    isVisible: showingTerminal,
                    sessionEpoch: terminalSessionEpoch,
                    onSessionEnded: handleShellExit,
                    onHide: hideTerminal
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(showingTerminal ? 1 : 0)
                .allowsHitTesting(showingTerminal)
                .accessibilityHidden(!showingTerminal)
            }
        }
    }

    // MARK: - Surfaces

    @ViewBuilder
    private var surfaceContent: some View {
        switch session.editorSurface {
        case .welcome:
            EditorWelcomeView(
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                runnerStatus: runnerStatus,
                onOpenSettings: onOpenSettings
            )
        case .emptyProject(let project):
            EditorEmptyStateView(project: project, onOpenFile: { session.openFile($0) })
        case .editing(let project, let file):
            EditorCanvasView(
                project: project,
                file: file,
                session: session,
                engine: engine,
                vfs: vfs
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            leadingToolbar
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 10) {
                terminalToggleButton
                Divider().frame(height: 16)
                InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
            }
        }
    }

    private var terminalToggleButton: some View {
        Button(action: toggleTerminal) {
            Image(systemName: showingTerminal
                ? "chevron.left.forwardslash.chevron.right"
                : "terminal")
        }
        .disabled(!canUseTerminal)
        .foregroundStyle(canUseTerminal ? Color.primary : Color.secondary.opacity(0.45))
        .accessibilityLabel(
            canUseTerminal
                ? (showingTerminal ? "Show Editor" : "Show Terminal")
                : "Terminal unavailable — open a project"
        )
        .help(
            canUseTerminal
                ? (showingTerminal ? "Show Editor (⌘J)" : "Show Terminal (⌘J)")
                : "Open a project to use the terminal"
        )
    }

    /// Sole ⌘J registration (not also on the toolbar button).
    private var terminalKeyboardShortcut: some View {
        Button("", action: toggleTerminal)
            .keyboardShortcut("j", modifiers: .command)
            .disabled(!canUseTerminal)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var leadingToolbar: some View {
        switch session.editorSurface {
        case .welcome:
            PlainToolbarLabel(title: "Welcome")
        case .emptyProject:
            EditorProjectSwitcher(session: session)
        case .editing(_, let file):
            HStack(spacing: 10) {
                EditorProjectSwitcher(session: session)
                PlainToolbarLabel(title: file.name)
            }
        }
    }

    // MARK: - Actions

    private func toggleCommander() {
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            showCommander.toggle()
        }
    }

    private func toggleTerminal() {
        guard canUseTerminal else { return }
        if showingTerminal { hideTerminal() } else { openTerminal() }
    }

    private func openTerminal() {
        guard canUseTerminal else { return }
        withAnimation(LayoutMetrics.panelSlideAnimation) { showTerminal = true }
    }

    private func hideTerminal() {
        withAnimation(LayoutMetrics.panelSlideAnimation) { showTerminal = false }
    }

    /// Remote shell `exit`: leave Terminal UI and invalidate keep-alive.
    private func handleShellExit() {
        hideTerminal()
        terminalSessionEpoch &+= 1
    }

    private func handleProjectChange(from oldID: String?, to newID: String?) {
        guard oldID != newID else { return }
        terminalSessionEpoch &+= 1
        if showTerminal { hideTerminal() }
    }
}
