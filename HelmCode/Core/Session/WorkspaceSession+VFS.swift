//
//  WorkspaceSession+VFS.swift
//  HelmCode
//
//  Apply remote VFS tree into the open-project session model.
//

import Foundation

extension WorkspaceSession {
    static let vfsProjectID = "vfs-remote"

    /// Install / refresh the remote workspace project from a nested VFS tree.
    /// Preserves the open file when the path still exists after a tree refresh.
    func applyVFSTree(_ tree: WorkspaceTreeNode, remoteRoot: String) {
        let project = WorkspaceProject(
            id: Self.vfsProjectID,
            name: tree.name,
            remote: remoteRoot,
            defaultBranch: "main",
            root: tree.asWorkspaceNode()
        )

        let previousSelection = selectedFileID
        let isFirstInstall = !projects.contains(where: { $0.id == Self.vfsProjectID })

        if let idx = projects.firstIndex(where: { $0.id == Self.vfsProjectID }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }

        if isFirstInstall || selectedProjectID == nil {
            openProject(Self.vfsProjectID)
            return
        }

        guard selectedProjectID == Self.vfsProjectID else { return }

        // Tree refresh: keep selection when possible (do not call openProject — it clears the file).
        if let previousSelection, project.root.find(id: previousSelection) == nil {
            selectedFileID = nil
        } else {
            selectedFileID = previousSelection
        }
        sourceControl = sourceControlByProject[Self.vfsProjectID]
    }

    /// Resolve relative VFS path for a node id in the active project.
    func vfsPath(forNodeID id: WorkspaceNode.ID) -> String? {
        selectedProject?.root.find(id: id)?.path
    }
}
