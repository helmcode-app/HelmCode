//
//  WorkspaceSession+VFS.swift
//  HelmCode
//
//  Apply remote VFS tree into the open-project session model.
//

import Foundation

extension WorkspaceSession {
    /// Alias for the remote VFS project id (see `WorkspaceProject.vfsRemoteID`).
    static var vfsProjectID: String { WorkspaceProject.vfsRemoteID }

    /// Install / refresh the remote workspace project from a nested VFS tree.
    /// Preserves the open file when the path still exists after a tree refresh.
    func applyVFSTree(_ tree: WorkspaceNode, remoteRoot: String) {
        let vfsID = WorkspaceProject.vfsRemoteID
        let project = WorkspaceProject(
            id: vfsID,
            name: tree.name,
            remote: remoteRoot,
            defaultBranch: "main",
            root: tree
        )

        let previousSelection = selectedFileID
        let isFirstInstall = !projects.contains(where: { $0.id == vfsID })

        if let idx = projects.firstIndex(where: { $0.id == vfsID }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }

        if isFirstInstall || selectedProjectID == nil {
            openProject(vfsID)
            return
        }

        guard selectedProjectID == vfsID else { return }

        // Tree refresh: keep selection when possible (do not call openProject — it clears the file).
        if let previousSelection, project.root.find(id: previousSelection) == nil {
            selectedFileID = nil
        } else {
            selectedFileID = previousSelection
        }
        sourceControl = sourceControlByProject[vfsID]
    }

    /// Resolve relative VFS path for a node id in the active project.
    func vfsPath(forNodeID id: WorkspaceNode.ID) -> String? {
        selectedProject?.root.find(id: id)?.path
    }
}
