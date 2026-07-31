//
//  BrowseProjectsSheet.swift
//  HelmCode
//
//  Full workspace list (welcome Recent → More).
//

import SwiftUI

struct BrowseProjectsSheet: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List(session.projects) { project in
                Button {
                    session.openProject(project.id)
                    isPresented = false
                } label: {
                    ProjectListLabel(
                        project: project,
                        secondary: .branchRemote,
                        runnerStatus: runnerStatus.displayStatus(
                            for: project,
                            engine: engine,
                            vfs: vfs
                        )
                    )
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
            .task {
                runnerStatus.refresh(projects: session.projects, engine: engine)
            }
        }
    }
}
