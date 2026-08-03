//
//  AgentPromptTagging.swift
//  HelmCode
//
//  `@path` tokens embedded in the agent prompt (contextPaths).
//

import Foundation

enum AgentPromptTagging {
    /// Token form embedded in the prompt, e.g. `@pkg/auth/login.go`.
    static func fileTag(for path: String) -> String {
        "@" + VFSPath.normalize(path)
    }

    /// Extract normalized paths from `@path` tokens in free-form prompt text.
    static func paths(in prompt: String) -> [String] {
        let pattern = /@([^\s@]+)/
        var result: [String] = []
        var seen = Set<String>()
        for match in prompt.matches(of: pattern) {
            let path = VFSPath.normalize(String(match.1))
            guard !path.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            result.append(path)
        }
        return result
    }
}
