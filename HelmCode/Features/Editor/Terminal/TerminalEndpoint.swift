//
//  TerminalEndpoint.swift
//  HelmCode
//
//  Resolve the HTTP base used to build `ws(s)://…/v1/terminal`.
//

import Foundation

enum TerminalEndpoint {
    /// Prefer project runner URL, then engine base, then app default.
    static func httpBase(projectRunnerURL: String?, engineBaseURL: String) -> String {
        let preferred = projectRunnerURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty {
            return RunnerURL.httpBase(from: preferred, fallback: engineBaseURL)
        }
        return RunnerURL.httpBase(
            from: engineBaseURL,
            fallback: RunnerConnectionPrefs.defaultURL
        )
    }
}
