//
//  EditorProjectSwitcher.swift
//  HelmCode
//
//  Center-column toolbar project menu.
//  Label = raster avatar (icon only) + full project name + chevron — never initials as title.
//

import SwiftUI

struct EditorProjectSwitcher: View {
    @ObservedObject var session: WorkspaceSession

    var body: some View {
        Menu {
            projectPickerItems
            if session.selectedProjectID != nil {
                Divider()
                Button("Close Project", role: .destructive) {
                    session.closeProject()
                }
            }
        } label: {
            toolbarLabel
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Project")
        .accessibilityValue(currentTitle)
        .accessibilityHint("Switch or close the open project")
    }

    // MARK: - Menu content

    @ViewBuilder
    private var projectPickerItems: some View {
        ForEach(session.projects) { project in
            Button {
                session.openProject(project.id)
            } label: {
                if project.id == session.selectedProjectID {
                    Label(project.displayName, systemImage: "checkmark")
                } else {
                    Text(project.displayName)
                }
            }
        }
    }

    // MARK: - Toolbar label (Image + Text only)

    private var toolbarLabel: some View {
        HStack(spacing: 6) {
            if let project = session.selectedProject {
                ProjectAvatarImage(project: project, size: ProjectAvatarMetrics.toolbar)
            } else {
                Image(systemName: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(currentTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    /// Full project name — initials belong only on the avatar image.
    private var currentTitle: String {
        session.selectedProject?.displayName ?? "Project"
    }
}
