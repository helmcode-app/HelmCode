//
//  AgentComposerBranches.swift
//  HelmCode
//
//  Current-branch label for the agent composer (read-only).
//

import Foundation

enum AgentComposerBranches {
    /// Live HEAD first (SCM, then project metadata), then the last seeded value.
    static func currentName(
        sourceControlBranch: String?,
        projectBranch: String?,
        fallback: String
    ) -> String {
        for raw in [sourceControlBranch, projectBranch, fallback] {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, trimmed != "—" { return trimmed }
        }
        return "branch"
    }
}
