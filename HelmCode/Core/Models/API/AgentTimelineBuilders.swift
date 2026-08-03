//
//  AgentTimelineBuilders.swift
//  HelmCode
//
//  Pure builders for local-only agent timeline nodes (user command, etc.).
//

import Foundation

enum AgentTimelineBuilders {
    /// Message body shown for a user-sent agent command in the session timeline.
    static func userCommandMessage(
        prompt: String,
        mode: AgentComposerMode,
        modelID: String,
        baseBranch: String,
        contextPaths: [String]
    ) -> String {
        var lines: [String] = []
        let branch = baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let metaBits = [
            mode.title,
            AgentModelOption.title(for: modelID),
            branch.isEmpty ? nil : "branch \(branch)",
        ].compactMap { $0 }
        if !metaBits.isEmpty {
            lines.append(metaBits.joined(separator: " · "))
        }
        lines.append(prompt)
        if !contextPaths.isEmpty {
            lines.append("")
            lines.append("Context:")
            for path in contextPaths {
                lines.append("  @\(path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Wire-compatible progress event used only on the client (never from runner-core).
    static func userCommandEvent(
        taskId: String,
        prompt: String,
        mode: AgentComposerMode,
        modelID: String,
        baseBranch: String,
        contextPaths: [String],
        at: Date = Date()
    ) -> TaskProgressEvent {
        TaskProgressEvent(
            taskId: taskId,
            status: .queued,
            message: userCommandMessage(
                prompt: prompt,
                mode: mode,
                modelID: modelID,
                baseBranch: baseBranch,
                contextPaths: contextPaths
            ),
            at: ISO8601DateFormatter.helm.string(from: at),
            stage: .userCommand,
            cycle: nil,
            detail: [
                "role": .string("user"),
                "mode": .string(mode.rawValue),
                "model": .string(modelID),
            ]
        )
    }
}
