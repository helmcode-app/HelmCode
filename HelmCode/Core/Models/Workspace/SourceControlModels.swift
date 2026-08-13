//
//  SourceControlModels.swift
//  HelmCode
//
//  Sidebar Source Control domain models.
//  Populated from runner vfs/gitStatus · vfs/gitRefs; center Diff uses vfs/gitShow + vfs/read.
//

import Foundation

// MARK: - Changes

enum GitChangeKind: String, Codable, Sendable, CaseIterable {
    case added
    case modified
    case deleted
    case untracked
    case renamed

    var shortCode: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .untracked: return "U"
        case .renamed: return "R"
        }
    }

    var title: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .untracked: return "Untracked"
        case .renamed: return "Renamed"
        }
    }

    var systemImage: String {
        switch self {
        case .added: return "plus"
        case .modified: return "pencil"
        case .deleted: return "minus"
        case .untracked: return "questionmark"
        case .renamed: return "arrow.right"
        }
    }

    init(vfsStatus: VFSGitChangeStatus) {
        switch vfsStatus {
        case .added: self = .added
        case .modified: self = .modified
        case .deleted: self = .deleted
        case .untracked: self = .untracked
        case .renamed: self = .renamed
        }
    }
}

struct GitChange: Identifiable, Hashable, Sendable {
    /// Stable path key used as id.
    var id: String { path }
    var path: String
    var kind: GitChangeKind
    var nodeID: WorkspaceNode.ID?
    var isStaged: Bool
    /// Previous path when kind == .renamed.
    var fromPath: String?

    var fileName: String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - Refs

enum GitRefKind: String, Sendable, Hashable {
    case localBranch
    case remoteBranch
    case tag

    var vfsKind: VFSGitRefKind {
        switch self {
        case .localBranch: return .localBranch
        case .remoteBranch: return .remoteBranch
        case .tag: return .tag
        }
    }

    var systemImage: String {
        switch self {
        case .localBranch, .remoteBranch: return "arrow.triangle.branch"
        case .tag: return "tag"
        }
    }
}

struct GitRef: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }
    var name: String
    var kind: GitRefKind
    /// Tip / pointed commit short SHA when known.
    var tip: String?
    /// True when this ref is the current HEAD (branch or exact tag).
    var isCurrent: Bool

    var systemImage: String { kind.systemImage }
}

// MARK: - State

enum SourceControlPhase: String, Sendable, Hashable {
    case loading
    case ready
    case unavailable
    case error
}

/// Center-column CodeMirror merge request (Source Control → Diff).
struct SourceControlDiffRequest: Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var kind: GitChangeKind
    var isStaged: Bool
    var fromPath: String?

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    init(change: GitChange) {
        path = change.path
        kind = change.kind
        isStaged = change.isStaged
        fromPath = change.fromPath
    }
}

struct SourceControlState: Hashable, Sendable {
    var phase: SourceControlPhase
    var branch: String
    /// Real tracking ref only — never invent `origin/<branch>`.
    var upstream: String?
    var ahead: Int?
    var behind: Int?
    var changes: [GitChange]
    var localBranches: [GitRef]
    var remoteBranches: [GitRef]
    var tags: [GitRef]
    var errorMessage: String?

    var changeCount: Int { changes.count }

    var sortedChanges: [GitChange] {
        changes.sorted { $0.path < $1.path }
    }

    static func empty(
        phase: SourceControlPhase = .loading,
        branch: String = "—"
    ) -> SourceControlState {
        SourceControlState(
            phase: phase,
            branch: branch,
            upstream: nil,
            ahead: nil,
            behind: nil,
            changes: [],
            localBranches: [],
            remoteBranches: [],
            tags: [],
            errorMessage: nil
        )
    }

    static func loading(for project: WorkspaceProject) -> SourceControlState {
        empty(phase: .loading, branch: project.displayBranch)
    }

    /// Align SCM branch label with project metadata (from VFS initialize).
    mutating func applyBranch(from project: WorkspaceProject) {
        branch = project.displayBranch
        markCurrentLocalBranch(named: project.trimmedBranch)
    }

    mutating func applyBranchName(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        branch = trimmed.isEmpty ? "—" : trimmed
        markCurrentLocalBranch(named: trimmed)
    }

    mutating func apply(
        status: VFSGitStatusResult,
        refs: VFSGitRefsResult,
        project: WorkspaceProject?
    ) {
        if !status.isRepo && !refs.isRepo {
            phase = .unavailable
            upstream = nil
            ahead = nil
            behind = nil
            changes = []
            localBranches = []
            remoteBranches = []
            tags = []
            errorMessage = nil
            if let project {
                branch = project.displayBranch
            }
            return
        }

        phase = .ready
        errorMessage = nil

        let branchTrimmed = status.branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !branchTrimmed.isEmpty {
            branch = branchTrimmed
        } else if let project {
            branch = project.displayBranch
        } else {
            branch = "—"
        }

        let upstreamTrimmed = status.upstream?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        upstream = upstreamTrimmed.isEmpty ? nil : upstreamTrimmed
        ahead = status.ahead
        behind = status.behind

        changes = status.changes.map { entry in
            GitChange(
                path: entry.path,
                kind: GitChangeKind(vfsStatus: entry.status),
                nodeID: project?.root.find(path: entry.path)?.id,
                isStaged: entry.staged,
                fromPath: entry.fromPath
            )
        }

        localBranches = refs.localBranches.map {
            GitRef(name: $0.name, kind: .localBranch, tip: $0.tip, isCurrent: $0.isCurrent)
        }
        remoteBranches = refs.remoteBranches.map {
            GitRef(name: $0.name, kind: .remoteBranch, tip: $0.tip, isCurrent: false)
        }
        tags = refs.tags.map {
            GitRef(name: $0.name, kind: .tag, tip: $0.tip, isCurrent: $0.isCurrent)
        }
    }

    private mutating func markCurrentLocalBranch(named name: String) {
        for i in localBranches.indices {
            localBranches[i].isCurrent = localBranches[i].name == name
        }
    }
}
