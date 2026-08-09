//
//  AgentNetworkEngine+Timeline.swift
//  HelmCode
//
//  History → EventLog ingest, streaming upserts, and synthetic local rows.
//

import Foundation

extension AgentNetworkEngine {

    // MARK: - History → timeline

    func applyHistory(_ history: SessionHistoryEnvelope, forDisplay: Bool = false) {
        let sid = history.sessionId
        if !forDisplay {
            activeTaskID = sid
        }

        for entry in history.entries {
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            ingestTimelineEntry(entry, sessionId: sid, forDisplay: forDisplay)
        }

        // Display-only restore: never leave phase/poll as Running.
        if forDisplay {
            return
        }

        if phase.isBusy {
            // Surface live activity while tools still run.
            let hasPendingAssistant = history.entries.contains { entry in
                (entry.role ?? "").lowercased() == "assistant"
                    && !timelineIDsBeforeTurn.contains(entry.id)
                    && entry.done != true
            }
            if hasPendingAssistant {
                pollStatus = .running
            }
        }

        if let session = history.session {
            switch session.status {
            case .failed:
                if phase.isBusy,
                   let message = history.entries.reversed().first(where: { entry in
                       let t = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                       guard !t.isEmpty else { return false }
                       guard !timelineIDsBeforeTurn.contains(entry.id) else { return false }
                       return (entry.kind ?? "") == "error" || (entry.role ?? "") == "system"
                   })?.text {
                    pollStatus = .failed
                    result = AgentResult.sessionSummary(
                        sessionId: sid,
                        status: .failed,
                        summary: message,
                        error: message
                    )
                    phase = .failed(message)
                    lastError = message
                    stopPolling()
                }
            case .cancelled:
                if phase.isBusy {
                    phase = .cancelled
                    pollStatus = .cancelled
                    stopPolling()
                }
            case .running, .completed, .idle, .unknown:
                break
            }
        }
    }

    func ingestTimelineEntry(
        _ entry: SessionTimelineEntry,
        sessionId: String,
        forDisplay: Bool
    ) {
        let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let role = (entry.role ?? "unknown").lowercased()
        let kind = (entry.kind ?? "message").lowercased()
        let stage: AgentEventStage
        let status: TaskStatus
        let done = entry.done ?? (role != "assistant")
        switch role {
        case "user":
            stage = .userCommand
            status = .running
        case "assistant":
            // Keep assistant stage so turn cards group reasoning/tools/answer together.
            stage = .llmInvoke
            status = done ? .succeeded : .running
        case "tool":
            stage = .testing
            status = done ? .succeeded : .running
        case "system":
            stage = .provisioning
            status = .running
        default:
            if kind == "error" {
                stage = .failed
                status = .failed
            } else {
                stage = .provisioning
                status = .running
            }
        }

        // Server echoes the user prompt: merge real `msg_…` id onto the optimistic
        // local bubble so Restore checkpoint works without duplicating the row.
        if stage == .userCommand,
           let idx = eventLog.firstIndex(where: {
               $0.stage == .userCommand && AgentTimelineBuilders.sameUserPrompt($0.message, text)
           }) {
            seenTimelineIDs.insert(entry.id)
            var detail = eventLog[idx].detail ?? [:]
            detail["timelineId"] = .string(entry.id)
            detail["role"] = .string("user")
            detail["kind"] = .string(kind.isEmpty ? "message" : kind)
            detail["done"] = .bool(true)
            detail["local"] = .bool(false)
            eventLog[idx] = eventLog[idx].updating(
                message: eventLog[idx].message,
                detail: detail,
                status: .succeeded
            )
            return
        }

        var detail: [String: JSONValue] = [
            "role": .string(role),
            "kind": .string(kind.isEmpty ? "message" : kind),
            "timelineId": .string(entry.id),
            "done": .bool(done),
        ]
        // Structured extras from runner mapper (reasoning / tools / answer).
        if let meta = entry.meta {
            if let reasoning = meta["reasoning"]?.stringValue, !reasoning.isEmpty {
                detail["reasoning"] = .string(reasoning)
            }
            if let answer = meta["answer"]?.stringValue, !answer.isEmpty {
                detail["answer"] = .string(answer)
            }
            if let tools = meta["tools"] {
                detail["tools"] = tools
            }
            // Rich tool rows: path + edit/write body for Cursor-style expansion.
            if let toolActions = meta["toolActions"] {
                detail["toolActions"] = toolActions
            }
        }
        // Pure reasoning messages: fold the body under Thought even without meta.
        if kind == "reasoning", detail["reasoning"] == nil {
            detail["reasoning"] = .string(text)
        }

        let event = TaskProgressEvent(
            taskId: sessionId,
            status: status,
            message: text,
            at: entry.at ?? ISO8601DateFormatter.helm.string(from: Date()),
            stage: stage,
            cycle: nil,
            detail: detail
        )
        ingestProgress(event, forDisplay: forDisplay)
    }

    func ingestProgress(_ event: TaskProgressEvent, forDisplay: Bool = false) {
        let logNode = EventLog(from: event, sequence: eventSequence + 1)

        // Upsert by stable timeline id so streaming assistant text updates in place.
        if let idx = eventLog.firstIndex(where: { $0.id == logNode.id }) {
            eventLog[idx] = eventLog[idx].updating(
                message: event.message,
                detail: event.detail,
                status: event.status
            )
        } else if let timelineId = event.detail?["timelineId"]?.stringValue,
                  seenTimelineIDs.contains(timelineId),
                  let idx = eventLog.firstIndex(where: {
                      $0.detail?["timelineId"]?.stringValue == timelineId
                  }) {
            eventLog[idx] = eventLog[idx].updating(
                message: event.message,
                detail: event.detail,
                status: event.status
            )
        } else {
            if let timelineId = event.detail?["timelineId"]?.stringValue {
                seenTimelineIDs.insert(timelineId)
            }
            eventSequence += 1
            eventLog.append(EventLog(from: event, sequence: eventSequence))
        }

        activeTaskID = event.taskId
        // Never flip to processing while only restoring history for display.
        if !forDisplay {
            if phase == .launching || phase == .ready || phase == .idle {
                phase = .processing
            }
            if phase.isBusy {
                // Keep footer on Running until the turn is fully done (tools may still run
                // after the first assistant text token).
                let eventDone = event.detail?["done"]?.boolValue ?? false
                if event.stage == .llmInvoke, !eventDone {
                    pollStatus = .running
                } else if phase.isBusy {
                    pollStatus = .running
                }
            }
        }
    }

    func appendSyntheticEvent(
        taskId: String,
        status: TaskStatus,
        stage: AgentEventStage,
        message: String
    ) {
        let event = TaskProgressEvent(
            taskId: taskId,
            status: status,
            message: message,
            at: ISO8601DateFormatter.helm.string(from: Date()),
            stage: stage,
            cycle: nil,
            detail: nil
        )
        ingestProgress(event)
    }

    func appendUserCommandEvent(
        taskId: String,
        prompt: String,
        mode: AgentComposerMode,
        modelID: String,
        contextPaths: [String]
    ) {
        ingestProgress(
            AgentTimelineBuilders.userCommandEvent(
                taskId: taskId,
                prompt: prompt,
                mode: mode,
                modelID: modelID,
                contextPaths: contextPaths
            )
        )
    }
}

// MARK: - Session → AgentResult bridge

extension AgentResult {
    static func sessionSummary(
        sessionId: String,
        status: TaskStatus,
        summary: String,
        error: String? = nil
    ) -> AgentResult {
        let now = ISO8601DateFormatter.helm.string(from: Date())
        return AgentResult(
            taskId: sessionId,
            status: status,
            branch: "",
            worktreePath: "",
            commitSha: nil,
            pushRemote: nil,
            testAttempts: [],
            summary: summary,
            error: error,
            startedAt: now,
            finishedAt: now,
            durationMs: 0
        )
    }
}
