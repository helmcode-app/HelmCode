//
//  SidebarFileTreeKeyboard.swift
//  HelmCode
//
//  Pure keyboard navigation for the Files outline (Finder / Xcode style).
//

import Foundation

enum SidebarFileTreeKeyboard {
    enum Action: Equatable {
        case expand(WorkspaceNode.ID)
        case collapse(WorkspaceNode.ID)
        case select(WorkspaceNode.ID)
        /// Select and open (files only; directories ignored by the view).
        case selectAndOpen(WorkspaceNode.ID)
        case openCurrent
        case none
    }

    static func leftArrow(
        selected: WorkspaceNode?,
        expandedIDs: Set<WorkspaceNode.ID>,
        root: WorkspaceNode
    ) -> Action {
        guard let node = selected else { return .none }
        if node.isDirectory, expandedIDs.contains(node.id) {
            return .collapse(node.id)
        }
        if let parent = SidebarFileTreeModel.parentID(of: node.id, in: root) {
            return .select(parent)
        }
        return .none
    }

    static func rightArrow(
        selected: WorkspaceNode?,
        expandedIDs: Set<WorkspaceNode.ID>
    ) -> Action {
        guard let node = selected, node.isDirectory else { return .none }
        if !expandedIDs.contains(node.id) {
            return .expand(node.id)
        }
        if let first = node.directoryChildren?.first {
            return .selectAndOpen(first.id)
        }
        return .none
    }

    static func move(
        delta: Int,
        selectedID: WorkspaceNode.ID?,
        rows: [SidebarFileTreeRow]
    ) -> Action {
        guard !rows.isEmpty else { return .none }
        let currentIndex = selectedID.flatMap { id in rows.firstIndex(where: { $0.id == id }) }
        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + delta, 0), rows.count - 1)
        } else {
            nextIndex = delta > 0 ? 0 : rows.count - 1
        }
        return .selectAndOpen(rows[nextIndex].id)
    }

    static func space(selected: WorkspaceNode?) -> Action {
        guard let node = selected else { return .none }
        if node.isDirectory {
            // Toggle expand handled by view with current expansion state.
            return .expand(node.id) // view treats expand on already-expanded as collapse via toggle
        }
        return .openCurrent
    }
}
