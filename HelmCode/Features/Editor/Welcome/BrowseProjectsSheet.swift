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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.projects.isEmpty {
                        Text("No projects yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        InsetGroupedCard {
                            ForEach(Array(session.projects.enumerated()), id: \.element.id) { index, project in
                                if index > 0 { InsetGroupedRowDivider() }
                                projectRow(project)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .helmInlineNavigationTitle("Projects")
            .helmSheetCloseToolbar {
                isPresented = false
            }
            .task {
                runnerStatus.refresh(projects: session.projects, engine: engine)
            }
            .projectSettingsSheet(
                projectID: $projectSettingsID,
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent
            )
        }
    }

    private func projectRow(_ project: WorkspaceProject) -> some View {
        Button {
            session.openProject(project.id)
            isPresented = false
        } label: {
            IconListRow(
                project: project,
                runnerStatus: runnerStatus.displayStatus(
                    for: project,
                    engine: engine,
                    vfs: vfs
                )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            ProjectListContextMenu(
                project: project,
                onProjectSettings: { projectSettingsID = project.id },
                onRemoveFromRecents: { session.removeFromRecents(project.id) },
                onRemoveProject: { session.removeProject(project.id) }
            )
        }
    }
}
