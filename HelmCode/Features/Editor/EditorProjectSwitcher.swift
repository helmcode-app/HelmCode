//
//  EditorProjectSwitcher.swift
//  HelmCode
//
//  Compact project menu for the center-column toolbar (left of the file name).
//

import SwiftUI

struct EditorProjectSwitcher: View {
    @ObservedObject var session: WorkspaceSession

    var body: some View {
        Menu {
            ForEach(session.projects) { project in
                Button {
                    session.openProject(project.id)
                } label: {
                    if project.id == session.selectedProjectID {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }

            if session.selectedProjectID != nil {
                Divider()
                Button("Close Project", role: .destructive) {
                    session.closeProject()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(currentTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Project")
        .accessibilityValue(currentTitle)
        .accessibilityHint("Switch or close the open project")
    }

    private var currentTitle: String {
        session.selectedProject?.name ?? "Project"
    }
}
