//
//  WorkspaceTreeMutations.swift
//  HelmCode
//
//  Immutable tree transforms for create / rename / delete in the workspace browser.
//

import Foundation

enum WorkspaceTreeError: LocalizedError, Equatable {
    case notFound
    case invalidName
    case nameExists
    case cannotModifyRoot
    case notADirectory

    var errorDescription: String? {
        switch self {
        case .notFound: return "Item not found."
        case .invalidName: return "Enter a valid name (no slashes)."
        case .nameExists: return "A file or folder with that name already exists."
        case .cannotModifyRoot: return "The project root cannot be modified."
        case .notADirectory: return "Parent is not a folder."
        }
    }
}

extension WorkspaceProject {
    func withRoot(_ root: WorkspaceNode) -> WorkspaceProject {
        WorkspaceProject(
            id: id,
            name: name,
            remote: remote,
            defaultBranch: defaultBranch,
            root: root,
            runnerBaseURL: runnerBaseURL
        )
    }
}

extension WorkspaceNode {
    static func sanitizeName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        guard !name.contains("/") && !name.contains(":") else { return nil }
        guard name != "." && name != ".." else { return nil }
        return name
    }

    static func makeFile(name: String, parentPath: String) -> WorkspaceNode {
        let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        return WorkspaceNode(
            id: "node-\(UUID().uuidString)",
            name: name,
            path: path,
            isDirectory: false,
            children: [],
            languageHint: FileLanguageHint.resolve(fileName: name)
        )
    }

    static func makeDirectory(name: String, parentPath: String) -> WorkspaceNode {
        let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        return WorkspaceNode(
            id: "node-\(UUID().uuidString)",
            name: name,
            path: path,
            isDirectory: true,
            children: [],
            languageHint: nil
        )
    }

    func parentID(of nodeID: WorkspaceNode.ID) -> WorkspaceNode.ID? {
        for child in children {
            if child.id == nodeID { return id }
            if let nested = child.parentID(of: nodeID) { return nested }
        }
        return nil
    }

    /// Directory that should own a new child relative to `anchorID`.
    /// - File anchor → its parent directory
    /// - Directory anchor → itself
    /// - nil / root → self when this is the project root
    func insertionParentID(for anchorID: WorkspaceNode.ID?) -> WorkspaceNode.ID {
        guard let anchorID, let anchor = find(id: anchorID) else { return id }
        if anchor.isDirectory { return anchor.id }
        return parentID(of: anchorID) ?? id
    }

    func inserting(
        _ child: WorkspaceNode,
        under parentID: WorkspaceNode.ID
    ) -> Result<WorkspaceNode, WorkspaceTreeError> {
        guard let parent = find(id: parentID) else { return .failure(.notFound) }
        guard parent.isDirectory else { return .failure(.notADirectory) }
        if parent.children.contains(where: { $0.name.caseInsensitiveCompare(child.name) == .orderedSame }) {
            return .failure(.nameExists)
        }
        let placed = child.rebasingPath(under: parent.path)
        guard let next = mapNode(id: parentID, transform: { dir in
            var kids = dir.children
            kids.append(placed)
            kids.sort(by: Self.browserOrder)
            return dir.withChildren(kids)
        }) else {
            return .failure(.notFound)
        }
        return .success(next)
    }

    func renaming(
        id: WorkspaceNode.ID,
        to rawName: String
    ) -> Result<(tree: WorkspaceNode, node: WorkspaceNode), WorkspaceTreeError> {
        guard id != self.id else { return .failure(.cannotModifyRoot) }
        guard let name = Self.sanitizeName(rawName) else { return .failure(.invalidName) }
        guard find(id: id) != nil else { return .failure(.notFound) }
        guard let parentID = parentID(of: id), let parent = find(id: parentID) else {
            return .failure(.notFound)
        }
        if parent.children.contains(where: {
            $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return .failure(.nameExists)
        }

        let parentPath = parent.path
        guard let renamedTree = mapNode(id: id, transform: { node in
            node.renamed(to: name, parentPath: parentPath)
        }) else {
            return .failure(.notFound)
        }
        // Keep siblings sorted after rename.
        guard let sorted = renamedTree.mapNode(id: parentID, transform: { dir in
            dir.withChildren(dir.children.sorted(by: Self.browserOrder))
        }) else {
            return .failure(.notFound)
        }
        guard let updated = sorted.find(id: id) else { return .failure(.notFound) }
        return .success((sorted, updated))
    }

    func removing(id: WorkspaceNode.ID) -> Result<(tree: WorkspaceNode, removed: WorkspaceNode), WorkspaceTreeError> {
        guard id != self.id else { return .failure(.cannotModifyRoot) }
        guard let removed = find(id: id) else { return .failure(.notFound) }
        guard let next = filterNode(removing: id) else { return .failure(.notFound) }
        return .success((next, removed))
    }

    func contains(id: WorkspaceNode.ID) -> Bool {
        find(id: id) != nil
    }

    /// Collect every file under this node (for delete cascade git status).
    func collectAllFiles() -> [WorkspaceNode] {
        if !isDirectory { return [self] }
        return children.flatMap { $0.collectAllFiles() }
    }

    // MARK: - Internals

    /// Folder-first, then name — `nonisolated` so pure tree sorts stay off MainActor.
    nonisolated private static func browserOrder(_ a: WorkspaceNode, _ b: WorkspaceNode) -> Bool {
        if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
        return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private func withChildren(_ children: [WorkspaceNode]) -> WorkspaceNode {
        WorkspaceNode(
            id: id,
            name: name,
            path: path,
            isDirectory: isDirectory,
            children: children,
            languageHint: languageHint
        )
    }

    private func renamed(to name: String, parentPath: String) -> WorkspaceNode {
        let newPath = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        let kids = children.map { $0.rebasingPath(under: newPath) }
        return WorkspaceNode(
            id: id,
            name: name,
            path: newPath,
            isDirectory: isDirectory,
            children: kids,
            languageHint: isDirectory ? nil : FileLanguageHint.resolve(fileName: name)
        )
    }

    private func rebasingPath(under parentPath: String) -> WorkspaceNode {
        let newPath = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        return WorkspaceNode(
            id: id,
            name: name,
            path: newPath,
            isDirectory: isDirectory,
            children: children.map { $0.rebasingPath(under: newPath) },
            languageHint: languageHint
        )
    }

    private func mapNode(
        id: WorkspaceNode.ID,
        transform: (WorkspaceNode) -> WorkspaceNode
    ) -> WorkspaceNode? {
        if self.id == id {
            return transform(self)
        }
        guard isDirectory else { return nil }
        var changed = false
        let kids = children.map { child -> WorkspaceNode in
            if let mapped = child.mapNode(id: id, transform: transform) {
                changed = true
                return mapped
            }
            return child
        }
        return changed ? withChildren(kids) : nil
    }

    private func filterNode(removing id: WorkspaceNode.ID) -> WorkspaceNode? {
        guard isDirectory else { return nil }
        var changed = false
        var kids: [WorkspaceNode] = []
        for child in children {
            if child.id == id {
                changed = true
                continue
            }
            if child.isDirectory, let filtered = child.filterNode(removing: id) {
                kids.append(filtered)
                if filtered != child { changed = true }
            } else {
                kids.append(child)
            }
        }
        return changed ? withChildren(kids) : nil
    }
}
