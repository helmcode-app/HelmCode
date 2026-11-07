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
    /// User override; omitted when never customized.
    let customName: String?
    let remote: String
    let defaultBranch: String
    let runnerBaseURL: String
    /// Stable runner identity. The device token is not stored here.
    let runnerId: String?
    /// Runner workspace id (`default` when omitted on older saves).
    let workspaceId: String?
    /// Legacy shared Bearer. Ignored on load.
    let apiToken: String?

    init(
        id: String,
        name: String,
        remote: String,
        defaultBranch: String,
        runnerBaseURL: String,
        customName: String? = nil,
        runnerId: String? = nil,
        workspaceId: String? = nil,
        apiToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.customName = customName
        self.remote = remote
        self.defaultBranch = defaultBranch
        self.runnerBaseURL = runnerBaseURL
        self.runnerId = runnerId
        self.workspaceId = workspaceId
        self.apiToken = apiToken
    }

    init?(project: WorkspaceProject) {
        guard let url = project.runnerBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty,
              RunnerURL.isValid(url) else {
            return nil
        }
        self.id = project.id
        self.name = project.name
        self.customName = project.customName
        self.remote = project.remote
        self.defaultBranch = project.defaultBranch
        self.runnerBaseURL = RunnerURL.normalizeHTTP(url)
        self.runnerId = project.runnerId
        self.workspaceId = project.workspaceId
        self.apiToken = nil
    }

    /// Placeholder tree until VFS reconnects and fills children.
    func asWorkspaceProject() -> WorkspaceProject {
        let label = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rootName: String = {
            if !label.isEmpty { return label }
            let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "project" : n
        }()
        return WorkspaceProject(
            id: id,
            name: name,
            remote: remote,
            defaultBranch: defaultBranch,
            root: WorkspaceNode.emptyRoot(name: rootName),
            runnerBaseURL: runnerBaseURL,
            customName: customName,
            runnerId: runnerId,
            workspaceId: workspaceId
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
