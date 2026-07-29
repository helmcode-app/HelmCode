//
//  OpenProjectSheet.swift
//  HelmCode
//
//  Modal list for picking a workspace (welcome “Open Project…”).
//

import SwiftUI

struct OpenProjectSheet: View {
    @ObservedObject var session: WorkspaceSession
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(session.projects) { project in
                Button {
                    session.openProject(project.id)
                    isPresented = false
                } label: {
                    ProjectListLabel(project: project, secondary: .branchRemote)
                        .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Open Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }
}
