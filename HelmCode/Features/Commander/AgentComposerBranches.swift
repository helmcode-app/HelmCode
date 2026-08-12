//
//  AgentComposerBranches.swift
//  HelmCode
//
//  Branch chip choices for the agent composer (UI-only preference).
//

import Foundation

enum AgentComposerBranches {
    /// Unique branch labels for the composer menu, current first, then common defaults.
    static func choices(
        current: String,
        projectBranch: String?,
        sourceControlBranch: String?
    ) -> [String] {
        var set: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !set.contains(t) else { return }
            set.append(t)
        }
        add(current)
        add(projectBranch)
        add(sourceControlBranch)
        add("main")
        add("master")
        add("develop")
        return set
    }

    static func displayTitle(_ branch: String) -> String {
        let b = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? "branch" : b
    }
}
