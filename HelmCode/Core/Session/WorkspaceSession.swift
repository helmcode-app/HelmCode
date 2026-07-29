//
//  WorkspaceSession.swift
//  HelmCode
//
//  In-memory workspace selection state (projects / open file).
//  Ready for future git, buffers, and multi-tab expansion.
//

import Foundation
import Combine

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var projects: [WorkspaceProject]
    @Published var selectedProjectID: WorkspaceProject.ID?
    @Published var selectedFileID: WorkspaceNode.ID?

    init(projects: [WorkspaceProject] = WorkspaceCatalog.projects) {
        self.projects = projects
        self.selectedProjectID = projects.first?.id
        self.selectedFileID = nil
    }

    var selectedProject: WorkspaceProject? {
        projects.first { $0.id == selectedProjectID } ?? projects.first
    }

    var selectedFile: WorkspaceNode? {
        guard let project = selectedProject, let id = selectedFileID else { return nil }
        return project.root.find(id: id)
    }

    func selectProject(_ id: WorkspaceProject.ID?) {
        selectedProjectID = id
        selectedFileID = nil
    }
}
