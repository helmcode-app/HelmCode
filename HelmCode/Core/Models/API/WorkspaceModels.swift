//
//  WorkspaceModels.swift
//  HelmCode
//
//  Codable contracts for runner-core `/v1/workspaces`.
//

import Foundation

enum HelmWorkspace {
    static let defaultID = "default"
}

struct WorkspaceDTO: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let path: String
    let kind: String
}

struct ListWorkspacesEnvelope: Decodable, Sendable {
    let workspaces: [WorkspaceDTO]
    let defaultWorkspaceId: String?
}
