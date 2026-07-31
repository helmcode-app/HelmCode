//
//  EditorDetailView.swift
//  HelmCode
//
//  NavigationSplitView detail: welcome → empty project → CodeMirror.
//  Project switcher sits in the leading toolbar, left of the file name.
//

import SwiftUI

struct EditorDetailView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    var onOpenSettings: (() -> Void)?

    @AppStorage(AppStorageKey.showCommander) private var showCommander = true

    var body: some View {
        surfaceContent
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    leadingToolbar
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
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
}
