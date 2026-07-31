//
//  SavedProjectRecord.swift
//  HelmCode
//
//  Lightweight project metadata persisted across launches.
//  File trees are not stored — reconnect via runner URL + vfs/initialize.
//

import Foundation

/// Disk form of a runner-backed project (Open Project → Self-hosted).
struct SavedProjectRecord: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let remote: String
    let defaultBranch: String
    let runnerBaseURL: String

    init(id: String, name: String, remote: String, defaultBranch: String, runnerBaseURL: String) {
        self.id = id
        self.name = name
        self.remote = remote
        self.defaultBranch = defaultBranch
        self.runnerBaseURL = runnerBaseURL
    }

    init?(project: WorkspaceProject) {
        guard let url = project.runnerBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty,
              RunnerURL.isValid(url) else {
            return nil
        }
        self.id = project.id
        self.name = project.name
        self.remote = project.remote
        self.defaultBranch = project.defaultBranch
        self.runnerBaseURL = RunnerURL.normalizeHTTP(url)
    }

    /// Placeholder tree until VFS reconnects and fills children.
    func asWorkspaceProject() -> WorkspaceProject {
        let rootName = name.isEmpty ? "project" : name
        return WorkspaceProject(
            id: id,
            name: name,
            remote: remote,
            defaultBranch: defaultBranch,
            root: WorkspaceNode.emptyRoot(name: rootName),
            runnerBaseURL: runnerBaseURL
        )
    }
}

extension WorkspaceNode {
    /// Empty project root used for persisted projects before VFS loads the real tree.
    static func emptyRoot(name: String) -> WorkspaceNode {
        WorkspaceNode(
            id: "root",
            name: name,
            path: "",
            isDirectory: true,
            children: [],
            languageHint: nil
        )
    }
}
