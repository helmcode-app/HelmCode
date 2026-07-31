//
//  WorkspaceCatalog.swift
//  HelmCode
//
//  Preview / sample helpers only. Runtime projects come from Open Project + disk cache.
//

import Foundation

enum WorkspaceCatalog: Sendable {
    /// Empty by design — demo seeds are no longer loaded into the session.
    nonisolated static let projects: [WorkspaceProject] = []

    /// Minimal project for SwiftUI previews (not used at runtime).
    nonisolated static var previewProject: WorkspaceProject {
        WorkspaceProject(
            id: "preview",
            name: "Preview",
            remote: "example.com/preview",
            defaultBranch: "main",
            root: WorkspaceNode.emptyRoot(name: "Preview"),
            runnerBaseURL: nil
        )
    }
}
