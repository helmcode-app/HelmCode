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
    @Binding var columnVisibility: NavigationSplitViewVisibility
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
            // While the sidebar is open its own trailing toggle is the collapse control.
            // Collapsed: leave the system expand button on this column's leading edge.
            .toolbar(removing: columnVisibility == .detailOnly ? nil : .sidebarToggle)
            .toolbar { detailToolbar }
            .background { terminalKeyboardShortcut }
            .onChange(of: session.selectedProjectID) { oldID, newID in
                handleProjectChange(from: oldID, to: newID)
            }
            .onChange(of: session.editorSurface) { _, surface in
                revealEditorIfNeeded(for: surface)
            }
            .onAppear {
                if !canUseTerminal, showTerminal {
                    applyTerminalVisibility(false)
                }
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
                    workspaceId: project.workspaceId,
                    sessionEpoch: terminalSessionEpoch,
                    onSessionEnded: handleShellExit,
                    onHide: hideTerminal,
                    onSendToAgent: { prompt in
                        agent.prompt = prompt
                        withAnimation(LayoutMetrics.panelSlideAnimation) {
                            showCommander = true
                        }
                    }
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
        case .viewingDiff(let project, let diff):
            SourceControlDiffView(
                project: project,
                request: diff,
                session: session,
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
            trailingToolbar
        }
    }

    /// Terminal | divider | Inspector.
    /// System nav bar still adds its own trailing inset after the last icon.
    private var trailingToolbar: some View {
        HStack(spacing: LayoutMetrics.DetailTrailingToolbar.itemSpacing) {
            terminalToggleButton
            Divider()
                .frame(height: LayoutMetrics.DetailTrailingToolbar.dividerHeight)
            InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
        }
        .padding(.leading, LayoutMetrics.DetailTrailingToolbar.leadingInset)
    }

    private var terminalToggleButton: some View {
        Button(action: toggleTerminal) {
            Image(systemName: showingTerminal
                ? "chevron.left.forwardslash.chevron.right"
                : "terminal")
        }
        .disabled(!canUseTerminal)
        .foregroundStyle(canUseTerminal ? Color.primary : Color.secondary.opacity(0.45))
        .accessibilityLabel(terminalAccessibilityLabel)
        .help(terminalHelp)
    }

    private var terminalAccessibilityLabel: String {
        guard canUseTerminal else {
            return "Terminal unavailable — open a project"
        }
        return showingTerminal ? "Show Editor" : "Show Terminal"
    }

    private var terminalHelp: String {
        guard canUseTerminal else {
            return "Open a project to use the terminal"
        }
        return showingTerminal ? "Show Editor (⌘J)" : "Show Terminal (⌘J)"
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
            HStack(spacing: LayoutMetrics.detailLeadingToolbarSpacing) {
                EditorProjectSwitcher(session: session)
                PlainToolbarLabel(title: file.name)
            }
        case .viewingDiff(_, let diff):
            HStack(spacing: LayoutMetrics.detailLeadingToolbarSpacing) {
                EditorProjectSwitcher(session: session)
                PlainToolbarLabel(title: "Diff · \(diff.fileName)")
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
        // Key commands can see a stale @AppStorage snapshot after WK bridge writes.
        if TerminalVisibilityStore.isShown {
            hideTerminal()
        } else {
            openTerminal()
        }
    }

    private func openTerminal() {
        guard canUseTerminal else { return }
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            applyTerminalVisibility(true)
        }
    }

    private func hideTerminal() {
        guard showingTerminal || TerminalVisibilityStore.isShown else { return }
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            applyTerminalVisibility(false)
        }
    }

    /// Sidebar / search / SCM asked for a file or diff while Terminal is front.
    private func revealEditorIfNeeded(for surface: EditorSurface) {
        switch surface {
        case .editing, .viewingDiff:
            hideTerminal()
        case .welcome, .emptyProject:
            break
        }
    }

    /// Keep `@AppStorage` and UserDefaults in lockstep (see TerminalVisibilityStore).
    private func applyTerminalVisibility(_ shown: Bool) {
        TerminalVisibilityStore.setShown(shown)
        showTerminal = shown
    }

    /// Remote shell `exit`: leave Terminal UI and invalidate keep-alive.
    private func handleShellExit() {
        // Persist first so the next ⌘J never toggles a phantom “open” session.
        applyTerminalVisibility(false)
        terminalSessionEpoch &+= 1
    }

    private func handleProjectChange(from oldID: String?, to newID: String?) {
        guard oldID != newID else { return }
        terminalSessionEpoch &+= 1
        if showTerminal || TerminalVisibilityStore.isShown {
            hideTerminal()
        }
    }
}
