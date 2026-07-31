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
    /// - Parameters:
    ///   - remoteRoot: Server workspace absolute path (internal only).
    ///   - gitRemote: Git origin display string from `vfs/initialize.remote`.
    func applyVFSTree(
        _ tree: WorkspaceNode,
        remoteRoot: String,
        gitRemote: String? = nil,
        runnerBaseURL: String? = nil
    ) {
        let vfsID = WorkspaceProject.vfsRemoteID
        let existing = projects.first(where: { $0.id == vfsID })
        let resolvedURL = runnerBaseURL ?? existing?.runnerBaseURL
        let displayRemote = WorkspaceProject.resolveDisplayRemote(
            gitRemote: gitRemote,
            previousRemote: existing?.remote,
            fallbackRoot: remoteRoot
        )
        let project = WorkspaceProject(
            id: vfsID,
            name: tree.name,
            remote: displayRemote,
            defaultBranch: "main",
            root: tree,
            runnerBaseURL: resolvedURL
        )

        let previousSelection = selectedFileID
        let previousPath = previousSelection.flatMap { id in
            if let node = existing?.root.find(id: id) { return node.path }
            return WorkspaceNode.pathFromVFSNodeID(id)
        }

        let isFirstInstall = existing == nil

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

        // Rebind by path first so atomic save (remove+create) never clears the editor.
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
