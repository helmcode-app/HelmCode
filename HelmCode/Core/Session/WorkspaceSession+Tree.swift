//
//  WorkspaceSession+Tree.swift
//  HelmCode
//
//  Create / rename / delete in the open project tree.
//

import Foundation

@MainActor
extension WorkspaceSession {
    @discardableResult
    func createFile(named rawName: String, relativeTo anchorID: WorkspaceNode.ID?) -> WorkspaceNode? {
        createNode(named: rawName, isDirectory: false, relativeTo: anchorID)
    }

    @discardableResult
    func createFolder(named rawName: String, relativeTo anchorID: WorkspaceNode.ID?) -> WorkspaceNode? {
        createNode(named: rawName, isDirectory: true, relativeTo: anchorID)
    }

    @discardableResult
    func renameNode(id: WorkspaceNode.ID, to rawName: String) -> WorkspaceNode? {
        guard var project = selectedProject else { return nil }
        let previousPath = project.root.find(id: id)?.path
        switch project.root.renaming(id: id, to: rawName) {
        case .failure(let error):
            lastTreeError = error.localizedDescription
            return nil
        case .success(let result):
            project = project.withRoot(result.tree)
            replaceOpenProject(project)
            if let previousPath {
                noteRename(from: previousPath, to: result.node)
            }
            lastTreeError = nil
            return result.node
        }
    }

    @discardableResult
    func deleteNode(id: WorkspaceNode.ID) -> Bool {
        guard var project = selectedProject else { return false }
        switch project.root.removing(id: id) {
        case .failure(let error):
            lastTreeError = error.localizedDescription
            return false
        case .success(let result):
            project = project.withRoot(result.tree)
            replaceOpenProject(project)
            if let sel = selectedFileID, project.root.find(id: sel) == nil {
                selectedFileID = nil
            }
            noteDelete(result.removed)
            removeBookmarks(nodeIDs: collectIDs(in: result.removed), projectID: project.id)
            lastTreeError = nil
            return true
        }
    }

    private func createNode(
        named rawName: String,
        isDirectory: Bool,
        relativeTo anchorID: WorkspaceNode.ID?
    ) -> WorkspaceNode? {
        guard var project = selectedProject else { return nil }
        guard let name = WorkspaceNode.sanitizeName(rawName) else {
            lastTreeError = WorkspaceTreeError.invalidName.localizedDescription
            return nil
        }
        let parentID = project.root.insertionParentID(for: anchorID)
        guard let parent = project.root.find(id: parentID) else {
            lastTreeError = WorkspaceTreeError.notFound.localizedDescription
            return nil
        }
        let node = isDirectory
            ? WorkspaceNode.makeDirectory(name: name, parentPath: parent.path)
            : WorkspaceNode.makeFile(name: name, parentPath: parent.path)

        switch project.root.inserting(node, under: parentID) {
        case .failure(let error):
            lastTreeError = error.localizedDescription
            return nil
        case .success(let tree):
            project = project.withRoot(tree)
            replaceOpenProject(project)
            noteCreate(node)
            if !isDirectory {
                selectedFileID = node.id
            }
            lastTreeError = nil
            return node
        }
    }
}
