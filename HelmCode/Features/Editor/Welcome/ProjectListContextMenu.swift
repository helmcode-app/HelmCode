//
//  ProjectListContextMenu.swift
//  HelmCode
//
//  Shared long-press / context menu for project rows.
//

import SwiftUI

struct ProjectListContextMenu: View {
    let project: WorkspaceProject
    var onProjectSettings: () -> Void
    var onRemoveFromRecents: (() -> Void)? = nil
    var onRemoveProject: () -> Void

    var body: some View {
        Button {
            onProjectSettings()
        } label: {
            Label("Project Settings…", systemImage: "gearshape")
        }

        if let onRemoveFromRecents {
            Button(role: .destructive) {
                onRemoveFromRecents()
            } label: {
                Label("Remove from Recents", systemImage: "clock.arrow.circlepath")
            }
        }

        Button(role: .destructive) {
            onRemoveProject()
        } label: {
            Label("Remove Project", systemImage: "folder.badge.minus")
        }
    }
}
