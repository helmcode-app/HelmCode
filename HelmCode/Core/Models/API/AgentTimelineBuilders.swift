//
//  AgentTimelineBuilders.swift
//  HelmCode
//
//  Pure builders for local-only agent timeline nodes (user command, etc.).
//

import Foundation

enum AgentTimelineBuilders {
    /// Body for a user turn. Keep **prompt-only** (optional @context).
    /// Mode / model live in composer chrome — not duplicated into the bubble
    /// (server history is plain text; embedding meta caused double user rows).
    static func userCommandMessage(
        prompt: String,
        contextPaths: [String]
    ) -> String {
        var lines: [String] = [prompt]
        if !contextPaths.isEmpty {
            lines.append("")
            lines.append("Context:")
            for path in contextPaths {
                lines.append("  @\(path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Local optimistic user row (client-only). Server user messages with the
    /// same prompt text are deduped in `AgentNetworkEngine`.
    static func userCommandEvent(
        taskId: String,
        prompt: String,
        mode: AgentComposerMode,
        modelID: String,
        contextPaths: [String],
        at: Date = Date()
    ) -> TaskProgressEvent {
        TaskProgressEvent(
            taskId: taskId,
            status: .queued,
            message: userCommandMessage(
                prompt: prompt,
                contextPaths: contextPaths
            ),
            at: ISO8601DateFormatter.helm.string(from: at),
            stage: .userCommand,
            cycle: nil,
            detail: [
                "role": .string("user"),
                "mode": .string(mode.rawValue),
                "model": .string(modelID),
                "prompt": .string(prompt),
                "local": .bool(true),
            ]
        )
    }

    /// Whether two user-facing bodies refer to the same prompt (ignores meta chrome).
    static func sameUserPrompt(_ a: String, _ b: String) -> Bool {
        normalizeUserPrompt(a) == normalizeUserPrompt(b)
    }

    static func normalizeUserPrompt(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip legacy "Agent · Model · branch …\n" header if still present.
        if let r = t.range(of: "\n") {
            let first = String(t[..<r.lowerBound])
            if first.contains(" · ") || first.hasPrefix("Agent") || first.hasPrefix("Ask") || first.hasPrefix("Plan") {
                t = String(t[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Drop trailing Context: block for comparison.
        if let range = t.range(of: "\n\nContext:") {
            t = String(t[..<range.lowerBound])
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
