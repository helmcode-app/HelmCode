//
//  WorkspaceSession+Bookmarks.swift
//  HelmCode
//
//  File/folder bookmarks (sidebar) + line bookmarks (editor).
//

import Foundation

@MainActor
extension WorkspaceSession {
    /// Bookmarks that still resolve in the open project (newest first).
    var activeBookmarks: [(bookmark: WorkspaceBookmark, node: WorkspaceNode)] {
        guard let project = selectedProject else { return [] }
        return bookmarks.compactMap { mark in
            guard mark.projectID == project.id,
                  let node = project.root.find(id: mark.nodeID) else { return nil }
            // Line bookmarks only apply to files.
            if mark.isLineBookmark, node.isDirectory { return nil }
            return (mark, node)
        }
    }

    /// Whole-file/folder bookmark present for this node (sidebar context menu).
    func isFileBookmarked(_ nodeID: WorkspaceNode.ID) -> Bool {
        guard let projectID = selectedProjectID else { return false }
        return bookmarks.contains {
            $0.projectID == projectID && $0.nodeID == nodeID && $0.isFileBookmark
        }
    }

    /// 1-based line bookmarks in `nodeID` (editor gutter only; excludes whole-file marks).
    func bookmarkedLines(in nodeID: WorkspaceNode.ID) -> [Int] {
        guard let projectID = selectedProjectID else { return [] }
        return bookmarks.compactMap { mark -> Int? in
            guard mark.projectID == projectID,
                  mark.nodeID == nodeID,
                  let line = mark.line else { return nil }
            return line
        }
        .sorted()
    }

    /// Open a bookmark: select node; for line marks, scroll editor via `pendingEditorRevealLine`.
    func openBookmark(_ bookmark: WorkspaceBookmark) {
        if selectedProjectID != bookmark.projectID {
            openProject(bookmark.projectID)
        }
        selectedFileID = bookmark.nodeID
        pendingEditorRevealLine = bookmark.line
    }

    /// Toggle a whole-file/folder bookmark (sidebar context menu).
    func toggleFileBookmark(nodeID: WorkspaceNode.ID) {
        guard let projectID = selectedProjectID,
              let project = selectedProject,
              project.root.contains(id: nodeID) else { return }

        if let idx = bookmarks.firstIndex(where: {
            $0.projectID == projectID && $0.nodeID == nodeID && $0.isFileBookmark
        }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(
                WorkspaceBookmark(projectID: projectID, nodeID: nodeID, line: nil),
                at: 0
            )
        }
        persistBookmarks()
    }

    /// Toggle a line bookmark at `line` (1-based) inside a file (editor).
    func toggleLineBookmark(nodeID: WorkspaceNode.ID, line: Int, lineText: String? = nil) {
        guard let projectID = selectedProjectID,
              let project = selectedProject,
              let node = project.root.find(id: nodeID),
              !node.isDirectory else { return }

        let line = max(1, line)
        if let idx = bookmarks.firstIndex(where: {
            $0.projectID == projectID && $0.nodeID == nodeID && $0.line == line
        }) {
            bookmarks.remove(at: idx)
        } else {
            let snippet = lineText?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = (snippet?.isEmpty == false) ? String(snippet!.prefix(120)) : nil
            bookmarks.insert(
                WorkspaceBookmark(projectID: projectID, nodeID: nodeID, line: line, lineText: trimmed),
                at: 0
            )
        }
        persistBookmarks()
    }

    func removeBookmark(_ bookmark: WorkspaceBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persistBookmarks()
    }

    func persistBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: AppStorageKey.workspaceBookmarks)
    }

    func removeBookmarks(nodeIDs: Set<WorkspaceNode.ID>, projectID: WorkspaceProject.ID) {
        let before = bookmarks.count
        bookmarks.removeAll { $0.projectID == projectID && nodeIDs.contains($0.nodeID) }
        if bookmarks.count != before { persistBookmarks() }
    }

    func pruneBookmarks(for project: WorkspaceProject) {
        let before = bookmarks.count
        bookmarks.removeAll { mark in
            mark.projectID == project.id && project.root.find(id: mark.nodeID) == nil
        }
        if bookmarks.count != before { persistBookmarks() }
    }
}
