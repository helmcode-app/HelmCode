//
//  SidebarFileTreeModel.swift
//  HelmCode
//
//  Flattened outline rows + expand state for keyboard-friendly Files navigator.
//

import Foundation

/// One visible row in the Files list (depth drives indent).
struct SidebarFileTreeRow: Identifiable, Hashable, Sendable {
    var id: WorkspaceNode.ID { node.id }
    let node: WorkspaceNode
    let depth: Int
}

enum SidebarFileTreeModel {
    /// Depth-first visible rows given which directories are expanded.
    static func visibleRows(
        roots: [WorkspaceNode],
        expandedIDs: Set<WorkspaceNode.ID>
    ) -> [SidebarFileTreeRow] {
        var rows: [SidebarFileTreeRow] = []
        append(nodes: roots, depth: 0, expandedIDs: expandedIDs, into: &rows)
        return rows
    }

    private static func append(
        nodes: [WorkspaceNode],
        depth: Int,
        expandedIDs: Set<WorkspaceNode.ID>,
        into rows: inout [SidebarFileTreeRow]
    ) {
        for node in nodes {
            rows.append(SidebarFileTreeRow(node: node, depth: depth))
            guard node.isDirectory,
                  expandedIDs.contains(node.id),
                  let children = node.directoryChildren,
                  !children.isEmpty else {
                continue
            }
            append(nodes: children, depth: depth + 1, expandedIDs: expandedIDs, into: &rows)
        }
    }

    /// Parent directory id for a node under `root` (nil for top-level).
    static func parentID(of id: WorkspaceNode.ID, in root: WorkspaceNode) -> WorkspaceNode.ID? {
        parentID(of: id, among: root.children, parent: nil)
    }

    private static func parentID(
        of id: WorkspaceNode.ID,
        among nodes: [WorkspaceNode],
        parent: WorkspaceNode.ID?
    ) -> WorkspaceNode.ID? {
        for node in nodes {
            if node.id == id { return parent }
            if node.isDirectory, let children = node.directoryChildren {
                if let hit = parentID(of: id, among: children, parent: node.id) {
                    return hit
                }
            }
        }
        return nil
    }

    /// Expand every ancestor of `id` so the row is visible.
    static func expandingAncestors(
        of id: WorkspaceNode.ID,
        in root: WorkspaceNode,
        into expanded: inout Set<WorkspaceNode.ID>
    ) {
        var path: [WorkspaceNode.ID] = []
        if collectPath(to: id, among: root.children, path: &path) {
            for ancestor in path.dropLast() {
                expanded.insert(ancestor)
            }
        }
    }

    private static func collectPath(
        to id: WorkspaceNode.ID,
        among nodes: [WorkspaceNode],
        path: inout [WorkspaceNode.ID]
    ) -> Bool {
        for node in nodes {
            path.append(node.id)
            if node.id == id { return true }
            if node.isDirectory, let children = node.directoryChildren {
                if collectPath(to: id, among: children, path: &path) {
                    return true
                }
            }
            path.removeLast()
        }
        return false
    }
}
