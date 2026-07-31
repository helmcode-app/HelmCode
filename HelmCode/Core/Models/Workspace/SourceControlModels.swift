//
//  SourceControlModels.swift
//  HelmCode
//
//  Lightweight SCM surface for the sidebar (local mock until real git is wired).
//

import Foundation

enum GitChangeKind: String, Codable, Sendable, CaseIterable {
    case added
    case modified
    case deleted
    case untracked

    var shortCode: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .untracked: return "U"
        }
    }

    var title: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .untracked: return "Untracked"
        }
    }

    var systemImage: String {
        switch self {
        case .added: return "plus.circle"
        case .modified: return "pencil.circle"
        case .deleted: return "minus.circle"
        case .untracked: return "questionmark.circle"
        }
    }
}

struct GitChange: Identifiable, Hashable, Sendable {
    /// Stable path key (before delete) used as id.
    var id: String { path }
    var path: String
    var kind: GitChangeKind
    var nodeID: WorkspaceNode.ID?
    var isStaged: Bool

    var fileName: String {
        (path as NSString).lastPathComponent
    }
}

struct SourceControlState: Hashable, Sendable {
    var branch: String
    var upstream: String?
    var changes: [GitChange]
    /// Last status toast / result for Pull / Push / Commit.
    var lastMessage: String?

    var staged: [GitChange] { changes.filter(\.isStaged).sorted { $0.path < $1.path } }
    var unstaged: [GitChange] { changes.filter { !$0.isStaged }.sorted { $0.path < $1.path } }
    var changeCount: Int { changes.count }

    /// Align SCM header with project metadata (live git branch from VFS).
    mutating func applyBranch(from project: WorkspaceProject) {
        branch = project.displayBranch
        upstream = project.displayUpstream
    }

    mutating func applyBranchName(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        branch = trimmed.isEmpty ? "—" : trimmed
        upstream = trimmed.isEmpty ? "—" : "origin/\(trimmed)"
    }

    static func seed(for project: WorkspaceProject) -> SourceControlState {
        // Demo dirty files so SCM isn't empty on first open.
        let candidates = project.root.collectFiles(limit: 8)
        let sample = Array(candidates.prefix(2))
        let changes: [GitChange] = sample.map { node in
            GitChange(path: node.path, kind: .modified, nodeID: node.id, isStaged: false)
        }
        return SourceControlState(
            branch: project.displayBranch,
            upstream: project.displayUpstream,
            changes: changes,
            lastMessage: nil
        )
    }
}
