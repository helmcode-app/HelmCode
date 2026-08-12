//
//  AgentTranscriptItem.swift
//  HelmCode
//
//  Group EventLog into user bubbles + agent turns for the chat transcript.
//

import Foundation

enum AgentTranscriptItem: Identifiable, Equatable {
    case user(EventLog)
    /// Consecutive non-user rows after a user prompt (thinking / tools / answer).
    case agentTurn(id: String, parts: [EventLog])

    var id: String {
        switch self {
        case .user(let e): return e.id
        case .agentTurn(let id, _): return "turn:\(id)"
        }
    }

    static func build(from log: [EventLog]) -> [AgentTranscriptItem] {
        var items: [AgentTranscriptItem] = []
        var buffer: [EventLog] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let key = buffer.compactMap { $0.detail?["timelineId"]?.stringValue }
                .filter { !$0.isEmpty }
                .joined(separator: "+")
            let id = key.isEmpty ? buffer.map(\.id).joined(separator: "+") : key
            items.append(.agentTurn(id: id, parts: buffer))
            buffer = []
        }

        for entry in log {
            if entry.stage == .userCommand {
                flushBuffer()
                items.append(.user(entry))
            } else {
                buffer.append(entry)
            }
        }
        flushBuffer()
        return items
    }
}
