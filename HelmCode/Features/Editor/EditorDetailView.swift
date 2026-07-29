//
//  EditorDetailView.swift
//  HelmCode
//
//  NavigationSplitView detail: editor + system toolbar
//  (filename + Commander inspector toggle). Sidebar toggle is system-injected.
//

import SwiftUI

struct EditorDetailView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine

    @AppStorage(AppStorageKey.showCommander) private var showCommander = true

    var body: some View {
        EditorCanvasView(
            project: session.selectedProject,
            file: session.selectedFile,
            engine: engine
        )
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                PlainToolbarLabel(title: editorFileTitle)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .topBarTrailing) {
                InspectorToggleButton(isExpanded: showCommander, action: toggleCommander)
            }
        }
    }

    private func toggleCommander() {
        withAnimation(LayoutMetrics.panelSlideAnimation) {
            showCommander.toggle()
        }
    }

    private var editorFileTitle: String {
        if let file = session.selectedFile, !file.isDirectory {
            return file.name
        }
        return "Editor"
    }
}
