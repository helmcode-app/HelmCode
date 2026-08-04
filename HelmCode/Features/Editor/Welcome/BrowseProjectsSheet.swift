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
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor
    @Binding var isPresented: Bool

    @State private var projectSettingsID: WorkspaceProject.ID?

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
                .contextMenu {
                    ProjectListContextMenu(
                        project: project,
                        onProjectSettings: { projectSettingsID = project.id },
                        onRemoveProject: { session.removeProject(project.id) }
                    )
                }
            }
            .helmInlineNavigationTitle("Projects")
            .helmSheetCloseToolbar {
                isPresented = false
            }
            .task {
                runnerStatus.refresh(projects: session.projects, engine: engine)
            }
            .sheet(isPresented: Binding(
                get: { projectSettingsID != nil },
                set: { if !$0 { projectSettingsID = nil } }
            )) {
                if let id = projectSettingsID {
                    ProjectSettingsSheet(
                        session: session,
                        engine: engine,
                        vfs: vfs,
                        agent: agent,
                        projectID: id,
                        isPresented: Binding(
                            get: { projectSettingsID != nil },
                            set: { if !$0 { projectSettingsID = nil } }
                        )
                    )
                }
            }
        }
    }
}
