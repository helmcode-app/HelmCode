//
//  ProjectSettingsError.swift
//  HelmCode
//
//  Errors from Project Settings / runner URL edits on WorkspaceSession.
//

import Foundation

enum ProjectSettingsError: LocalizedError, Equatable {
    case projectNotFound
    case invalidRunnerURL
    case runnerURLInUse(String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound:
            return "Project not found."
        case .invalidRunnerURL:
            return "Enter a valid runner URL (http:// or https://)."
        case .runnerURLInUse(let name):
            return "That runner URL is already used by “\(name)”."
        }
    }
}
