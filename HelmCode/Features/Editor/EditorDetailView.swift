//
//  EditorDetailView.swift
//  HelmCode
//
//  NavigationSplitView detail routing:
//  welcome (no project) → empty project (no file) → CodeMirror canvas.
//

import SwiftUI

struct EditorDetailView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    var onOpenSettings: (() -> Void)?

    @AppStorage(AppStorageKey.showCommander) private var showCommander = true

    /// Center-column surface driven by session selection.
    private enum Surface: Equatable {
        case welcome
        case projectEmpty
        case editor
    }

    private var surface: Surface {
        if session.selectedProjectID == nil { return .welcome }
        if session.showsProjectEmptyState { return .projectEmpty }
        return .editor
    }

    var body: some View {
        surfaceContent
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    PlainToolbarLabel(title: toolbarTitle)
                }
                .sharedBackgroundVisibility(.hidden)

                ToolbarItem(placement: .topBarTrailing) {
                    InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
                }
            }
    }

    @ViewBuilder
    private var surfaceContent: some View {
        switch surface {
        case .welcome:
            EditorWelcomeView(session: session, onOpenSettings: onOpenSettings)
        case .projectEmpty:
            if let project = session.selectedProject {
                EditorEmptyStateView(project: project, onOpenFile: session.openFile)
            } else {
                EditorWelcomeView(session: session, onOpenSettings: onOpenSettings)
            }
        case .editor:
            EditorCanvasView(
                project: session.selectedProject,
                file: session.selectedFile,
                engine: engine
            )
        }
    }

    private func toggleCommander() {
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            showCommander.toggle()
        }
    }

    private var toolbarTitle: String {
        switch surface {
        case .welcome:
            return "Welcome"
        case .projectEmpty:
            return session.selectedProject?.name ?? "Editor"
        case .editor:
            if let file = session.selectedFile, !file.isDirectory {
                return file.name
            }
            return session.selectedProject?.name ?? "Editor"
        }
    }
}
