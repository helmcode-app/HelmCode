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
        let previousPath: String? = {
            guard let id = previousSelection else { return nil }
            if let existing = projects.first(where: { $0.id == vfsID })?.root.find(id: id) {
                return existing.path
            }
            if id.hasPrefix("vfs:") { return String(id.dropFirst(4)) }
            return nil
        }()

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

        // Tree refresh: rebind by path first so atomic save (remove+create) and
        // re-walked trees never bounce the center column to empty state.
        if let path = previousPath, let node = project.root.find(path: path) {
            selectedFileID = node.id
        } else if let previousSelection, project.root.find(id: previousSelection) != nil {
            selectedFileID = previousSelection
        } else if previousSelection != nil {
            // Keep id; `selectedFile` synthesizes a stub if the node is mid-refresh.
            selectedFileID = previousSelection
        }
        sourceControl = sourceControlByProject[vfsID]
    }

    /// Resolve relative VFS path for a node id in the active project.
    func vfsPath(forNodeID id: WorkspaceNode.ID) -> String? {
        selectedProject?.root.find(id: id)?.path
    }
}
