//
//  WorkspaceNode.swift
//  HelmCode
//
//  Workspace tree types for the sidebar browser.
//

import Foundation

struct WorkspaceProject: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let remote: String
    let defaultBranch: String
    let root: WorkspaceNode
}

struct WorkspaceNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [WorkspaceNode]
    let languageHint: String?

    var systemImage: String {
        if isDirectory { return "folder.fill" }
        switch languageHint {
        case "swift": return "swift"
        case "ts", "js": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md": return "doc.richtext"
        case "go": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    /// `OutlineGroup` expects optional children — files yield `nil`.
    var directoryChildren: [WorkspaceNode]? {
        isDirectory ? children : nil
    }

    func find(id: WorkspaceNode.ID) -> WorkspaceNode? {
        if self.id == id { return self }
        for child in children {
            if let hit = child.find(id: id) { return hit }
        }
        return nil
    }
}
