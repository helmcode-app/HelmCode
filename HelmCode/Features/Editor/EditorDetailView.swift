//
//  EditorDetailView.swift
//  HelmCode
//
//  NavigationSplitView detail: welcome → empty project → CodeMirror, or full-column Terminal.
//  Top toolbar (⌘J) toggles exclusive Code ↔ Terminal in the center column.
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
    }

    // MARK: - Center column (editor XOR terminal)

    @ViewBuilder
    private var centerColumn: some View {
        if showTerminal {
            TerminalPanelView(
                engine: engine,
                isPresented: terminalPresented
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else {
            surfaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        }
    }

    private var terminalPresented: Binding<Bool> {
        Binding(
            get: { showTerminal },
            set: { newValue in
                withAnimation(LayoutMetrics.panelSlideAnimation) {
                    showTerminal = newValue
                }
            }
        )
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
            // HStack so Divider is vertical; ToolbarItemGroup can stack and turn it into a hairline.
            HStack(spacing: 10) {
                terminalToggleButton
                Divider()
                    .frame(height: 16)
                InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
            }
        }
    }

    private var terminalToggleButton: some View {
        Button(action: toggleTerminal) {
            // Destination icon: Code when on Terminal, Terminal when on editor.
            Image(systemName: showTerminal
                ? "chevron.left.forwardslash.chevron.right"
                : "terminal")
        }
        .accessibilityLabel(showTerminal ? "Show Editor" : "Show Terminal")
        .help(showTerminal ? "Show Editor (⌘J)" : "Show Terminal (⌘J)")
        .keyboardShortcut("j", modifiers: .command)
    }

    /// Global ⌘J even when the toolbar button is not the focus target.
    private var terminalKeyboardShortcut: some View {
        Button("", action: toggleTerminal)
            .keyboardShortcut("j", modifiers: .command)
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

    private func toggleCommander() {
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            showCommander.toggle()
        }
    }

    private func toggleTerminal() {
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            showTerminal.toggle()
        }
    }
}
