//
//  BrowseProjectsSheet.swift
//  HelmCode
//
//  Full workspace list (welcome Recent → More).
//

import SwiftUI

struct BrowseProjectsSheet: View {
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
            .navigationTitle("Projects")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .helmSheetCloseToolbar {
                isPresented = false
            }
        }
    }
}
