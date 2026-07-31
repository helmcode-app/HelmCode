//
//  WorkspaceNode.swift
//  HelmCode
//
//  Workspace tree types for the sidebar browser.
//

import Foundation

struct WorkspaceProject: Identifiable, Hashable, Sendable {
    /// Legacy single-slot id (migration only; new projects use `stableID(forRunnerBaseURL:)`).
    static let vfsRemoteID = "vfs-remote"

    let id: String
    let name: String
    let remote: String
    let defaultBranch: String
    let root: WorkspaceNode
    /// Runner-core HTTP base URL for this project (`nil` = no remote API / not a real workspace).
    let runnerBaseURL: String?

    init(
        id: String,
        name: String,
        remote: String,
        defaultBranch: String,
        root: WorkspaceNode,
        runnerBaseURL: String? = nil
    ) {
        self.id = id
        self.name = name
        self.remote = remote
        self.defaultBranch = defaultBranch
        self.root = root
        self.runnerBaseURL = runnerBaseURL
    }

    /// Stable id for a self-hosted runner URL (survives restarts; one project per URL).
    static func stableID(forRunnerBaseURL raw: String) -> String {
        let normalized = RunnerURL.normalizeHTTP(raw).lowercased()
        let data = Data(normalized.utf8)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "r-\(encoded)"
    }

    /// Remote workspace backed by runner-core VFS (has a runner URL).
    var isVFSRemote: Bool {
        normalizedRunnerURL != nil
    }

    /// Normalized runner URL for connectivity probes / matching the active engine.
    var normalizedRunnerURL: String? {
        guard let raw = runnerBaseURL, RunnerURL.isValid(raw) else { return nil }
        return RunnerURL.normalizeHTTP(raw)
    }

    /// Normalized branch string (empty when unknown / detached).
    var trimmedBranch: String {
        defaultBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// UI label for branch (`—` when empty).
    var displayBranch: String {
        trimmedBranch.isEmpty ? "—" : trimmedBranch
    }

    /// UI upstream label (`origin/<branch>` or `—`).
    var displayUpstream: String {
        trimmedBranch.isEmpty ? "—" : "origin/\(trimmedBranch)"
    }

    /// e.g. `main  ·  github.com/…` (omits empty branch).
    var branchRemoteLine: String {
        let branch = trimmedBranch
        if branch.isEmpty { return remote }
        if remote.isEmpty { return branch }
        return "\(branch)  ·  \(remote)"
    }

    /// Live branch from runner wins; only fall back to cache when server omitted it.
    static func resolveBranch(live: String?, previous: String?) -> String {
        let liveTrimmed = live?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !liveTrimmed.isEmpty { return liveTrimmed }
        return previous?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Prefer git origin for UI; avoid showing container mount paths when possible.
    static func resolveDisplayRemote(
        gitRemote: String?,
        previousRemote: String?,
        fallbackRoot: String
    ) -> String {
        let trimmed = gitRemote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let previousRemote,
           !previousRemote.isEmpty,
           previousRemote != fallbackRoot,
           !previousRemote.hasPrefix("/") {
            return previousRemote
        }
        return fallbackRoot
    }

    func with(
        name: String? = nil,
        remote: String? = nil,
        defaultBranch: String? = nil,
        root: WorkspaceNode? = nil,
        runnerBaseURL: String? = nil
    ) -> WorkspaceProject {
        WorkspaceProject(
            id: id,
            name: name ?? self.name,
            remote: remote ?? self.remote,
            defaultBranch: defaultBranch ?? self.defaultBranch,
            root: root ?? self.root,
            runnerBaseURL: runnerBaseURL ?? self.runnerBaseURL
        )
    }
}

struct WorkspaceNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let children: [WorkspaceNode]
    let languageHint: String?

    /// Generic document icon (unfilled) for menus / empty-state chips.
    var systemImage: String {
        if isDirectory { return "folder.fill" }
        return FileLanguageHint.systemImageName(forLanguageHint: languageHint, filled: false)
    }

    /// Sidebar / list tree icon (filled document when generic).
    var sidebarSystemImage: String {
        if isDirectory { return "folder.fill" }
        return FileLanguageHint.systemImageName(forLanguageHint: languageHint, filled: true)
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

    func find(path: String) -> WorkspaceNode? {
        if self.path == path { return self }
        for child in children {
            if let hit = child.find(path: path) { return hit }
        }
        return nil
    }

    /// Depth-first list of non-directory nodes (e.g. Quick Open suggestions).
    func collectFiles(limit: Int) -> [WorkspaceNode] {
        guard limit > 0 else { return [] }
        var result: [WorkspaceNode] = []
        collectFiles(into: &result, limit: limit)
        return result
    }

    private func collectFiles(into result: inout [WorkspaceNode], limit: Int) {
        guard result.count < limit else { return }
        if !isDirectory {
            result.append(self)
            return
        }
        for child in children {
            child.collectFiles(into: &result, limit: limit)
            if result.count >= limit { return }
        }
    }

    /// Stable leaf used when a VFS tree refresh briefly drops a path (atomic save, re-walk).
    /// Id form: `vfs:<relative/path>`.
    static func vfsPlaceholder(path: String, id: String? = nil) -> WorkspaceNode {
        let normalized = VFSPath.normalize(path)
        let name = VFSPath.fileName(of: normalized)
        return WorkspaceNode(
            id: id ?? "vfs:\(normalized)",
            name: name,
            path: normalized,
            isDirectory: false,
            children: [],
            languageHint: FileLanguageHint.resolve(fileName: name)
        )
    }

    /// Extract relative path from a `vfs:…` node id, if present.
    static func pathFromVFSNodeID(_ id: WorkspaceNode.ID) -> String? {
        guard id.hasPrefix("vfs:") else { return nil }
        let path = String(id.dropFirst(4))
        return path.isEmpty ? nil : path
    }
}
