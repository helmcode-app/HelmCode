//
//  SidebarView.swift
//  HelmCode
//
//  NavigationSplitView sidebar:
//  Projects when none open; Files tree when a project is open.
//  Settings dock stays pinned at the bottom.
//

import SwiftUI

struct SidebarView: View {
    @ObservedObject var session: WorkspaceSession
    var onOpenSettings: () -> Void

    var body: some View {
        List(selection: $session.selectedFileID) {
            if let project = session.selectedProject {
                filesSection(project)
            } else {
                projectsSection
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            settingsDock
        }
    }

    // MARK: - Sections

    private func filesSection(_ project: WorkspaceProject) -> some View {
        Section {
            OutlineGroup(project.root.children, children: \.directoryChildren) { node in
                Label {
                    Text(node.name)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: node.systemImage)
                        .foregroundStyle(node.isDirectory ? Color.accentColor : .secondary)
                }
                .tag(node.id)
                .accessibilityLabel(node.path)
            }
        } header: {
            HStack {
                Text("Files")
                Spacer()
                Text(project.defaultBranch)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text(project.remote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var projectsSection: some View {
        Section {
            ForEach(session.projects) { project in
                Button {
                    session.openProject(project.id)
                } label: {
                    ProjectListLabel(project: project, secondary: .remote)
                }
            }
        } header: {
            Text("Projects")
        } footer: {
            Text("Open a project to browse files, or use the welcome page.")
                .font(.caption2)
        }
    }

    private var settingsDock: some View {
        List {
            Section {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityHint("Opens app settings")
            }
        }
        .listStyle(.sidebar)
        .scrollDisabled(true)
        .frame(maxHeight: 56)
        .scrollIndicators(.hidden)
    }
}
