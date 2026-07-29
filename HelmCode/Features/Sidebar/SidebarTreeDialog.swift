//
//  SidebarTreeDialog.swift
//  HelmCode
//
//  Create / rename / delete prompts for the workspace file tree.
//

import SwiftUI

enum SidebarTreeDialog: Identifiable, Equatable {
    case newFile(anchorID: WorkspaceNode.ID?)
    case newFolder(anchorID: WorkspaceNode.ID?)
    case rename(nodeID: WorkspaceNode.ID, currentName: String)
    case delete(nodeID: WorkspaceNode.ID, name: String, isDirectory: Bool)

    var id: String {
        switch self {
        case .newFile(let anchor): return "new-file-\(anchor ?? "root")"
        case .newFolder(let anchor): return "new-folder-\(anchor ?? "root")"
        case .rename(let id, _): return "rename-\(id)"
        case .delete(let id, _, _): return "delete-\(id)"
        }
    }

    var title: String {
        switch self {
        case .newFile: return "New File"
        case .newFolder: return "New Folder"
        case .rename: return "Rename"
        case .delete(_, _, let isDirectory):
            return isDirectory ? "Delete Folder" : "Delete File"
        }
    }

    var confirmTitle: String {
        switch self {
        case .newFile, .newFolder: return "Create"
        case .rename: return "Rename"
        case .delete: return "Delete"
        }
    }

    /// Prefill for the name field when the dialog opens.
    var defaultNameDraft: String {
        switch self {
        case .newFile: return "Untitled.swift"
        case .newFolder: return "NewFolder"
        case .rename(_, let current): return current
        case .delete: return ""
        }
    }

    var message: String {
        switch self {
        case .newFile, .newFolder:
            return "Created next to the selection, or in the project root."
        case .rename(_, let current):
            return "Rename “\(current)”."
        case .delete(_, let name, let isDirectory):
            return isDirectory
                ? "Delete folder “\(name)” and all of its contents? This cannot be undone."
                : "Delete file “\(name)”? This cannot be undone."
        }
    }

    var usesNameField: Bool {
        switch self {
        case .newFile, .newFolder, .rename: return true
        case .delete: return false
        }
    }

    /// Apply the dialog action against the session. Returns whether the action was destructive confirm.
    @MainActor
    func apply(to session: WorkspaceSession, nameDraft: String) {
        switch self {
        case .newFile(let anchor):
            _ = session.createFile(named: nameDraft, relativeTo: anchor)
        case .newFolder(let anchor):
            _ = session.createFolder(named: nameDraft, relativeTo: anchor)
        case .rename(let id, _):
            _ = session.renameNode(id: id, to: nameDraft)
        case .delete(let id, _, _):
            _ = session.deleteNode(id: id)
        }
    }
}
