//
//  AgentTurnContent.swift
//  HelmCode
//
//  Pure partition of EventLog parts into thought / tools / answer for one agent turn.
//  Timing helpers stay here so AgentTurnCard remains layout-only.
//

import Foundation

struct AgentTurnContent: Equatable {
    var thought: String
    var tools: [AgentToolAction]
    var answer: String

    static func partition(parts: [EventLog]) -> AgentTurnContent {
        var thoughts: [String] = []
        var tools: [AgentToolAction] = []
        var answers: [String] = []
        var intermediateAnswers: [String] = []

        for p in parts {
            let kind = (p.detail?["kind"]?.stringValue ?? "message").lowercased()
            let msg = p.message.trimmingCharacters(in: .whitespacesAndNewlines)

            let structured = AgentToolAction.parse(from: p.detail)
            if !structured.isEmpty {
                tools.append(contentsOf: structured)
            } else {
                tools.append(contentsOf: AgentToolAction.parseLegacyLabels(from: p.detail))
            }

            if let r = p.detail?["reasoning"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !r.isEmpty {
                thoughts.append(r)
            } else if kind == "reasoning", !msg.isEmpty, msg != "Working…" {
                thoughts.append(msg)
            }

            if kind == "tool" || p.stage == .testing {
                continue
            }
            if msg.hasPrefix("[tool:") {
                continue
            }

            if let answer = p.detail?["answer"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !answer.isEmpty {
                answers.append(answer)
                continue
            }

            if kind == "message" || kind == "unknown" || kind.isEmpty {
                guard !msg.isEmpty, msg != "Working…" else { continue }
                if let r = p.detail?["reasoning"]?.stringValue, r == msg { continue }
                if AgentChatFormatting.looksLikeRawToolNoise(msg) { continue }
                intermediateAnswers.append(msg)
            }
        }

        if answers.isEmpty, !intermediateAnswers.isEmpty {
            if intermediateAnswers.count == 1 {
                answers = intermediateAnswers
            } else {
                thoughts.append(contentsOf: intermediateAnswers.dropLast())
                answers = [intermediateAnswers.last!]
            }
        } else if !intermediateAnswers.isEmpty {
            thoughts.append(contentsOf: intermediateAnswers)
        }

        return AgentTurnContent(
            thought: dedupeJoin(thoughts),
            tools: AgentToolAction.dedupe(tools),
            answer: dedupeJoin(answers)
        )
    }

    static func isRunning(_ parts: [EventLog]) -> Bool {
        parts.contains { ($0.detail?["done"]?.boolValue ?? true) == false }
            || parts.contains {
                $0.message == "Working…" && ($0.detail?["done"]?.boolValue ?? false) == false
            }
    }

    static func spanSeconds(for rows: [EventLog], now: Date, isRunning: Bool) -> TimeInterval {
        let stamps = rows.map(\.timestamp).filter { $0 != .distantPast }
        let arrived = rows.map(\.arrivedAt)
        var best: TimeInterval = 0
        if let s0 = stamps.min(), let s1 = stamps.max() {
            let end = isRunning ? now : s1
            best = max(best, end.timeIntervalSince(s0))
        }
        if let a0 = arrived.min(), let a1 = arrived.max() {
            let end = isRunning ? now : a1
            best = max(best, end.timeIntervalSince(a0))
        }
        return max(0, best)
    }

    static func thoughtSeconds(
        parts: [EventLog],
        thoughtText: String,
        totalSeconds: TimeInterval,
        now: Date,
        isRunning: Bool
    ) -> TimeInterval {
        let thoughtParts = parts.filter { p in
            let kind = (p.detail?["kind"]?.stringValue ?? "").lowercased()
            if kind == "reasoning" { return true }
            if let r = p.detail?["reasoning"]?.stringValue, !r.isEmpty { return true }
            return false
        }
        if !thoughtParts.isEmpty {
            return max(spanSeconds(for: thoughtParts, now: now, isRunning: isRunning), 0.1)
        }
        if !thoughtText.isEmpty, totalSeconds > 0 {
            return max(min(totalSeconds * 0.45, totalSeconds - 0.1), 0.1)
        }
        return 0
    }

    private static func dedupeJoin(_ chunks: [String]) -> String {
        var seen = Set<String>()
        return chunks.filter { seen.insert($0).inserted }.joined(separator: "\n\n")
    }
}
