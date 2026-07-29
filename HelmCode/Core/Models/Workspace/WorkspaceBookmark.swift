//
//  WorkspaceBookmark.swift
//  HelmCode
//
//  Per-project bookmark: stable node id within that project.
//

import Foundation

struct WorkspaceBookmark: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(projectID)|\(nodeID)" }
    let projectID: WorkspaceProject.ID
    let nodeID: WorkspaceNode.ID
}
