//
//  WorkspaceNode.swift
//  HelmCode
//
//  Workspace tree types for the sidebar browser.
//

import Foundation

struct WorkspaceProject: Identifiable, Hashable, Sendable {
    /// Id for the single remote runner-core VFS workspace project.
    static let vfsRemoteID = "vfs-remote"

    let id: String
    let name: String
    let remote: String
    let defaultBranch: String
    let root: WorkspaceNode
    /// Runner-core HTTP base URL for this project (`nil` = local/demo, no remote API).
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

    /// Remote runner-core VFS project (single active remote workspace today).
    var isVFSRemote: Bool {
        id == Self.vfsRemoteID
    }

    /// Normalized runner URL for connectivity probes / matching the active engine.
    var normalizedRunnerURL: String? {
        guard let raw = runnerBaseURL, RunnerURL.isValid(raw) else { return nil }
        return RunnerURL.normalizeHTTP(raw)
    }

    /// e.g. `main  ·  github.com/…`
    var branchRemoteLine: String {
        "\(defaultBranch)  ·  \(remote)"
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
