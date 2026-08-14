//
//  AgentNetworkEngine+Launch.swift
//  HelmCode
//
//  Prompt launch + cancel for an agent turn.
//  Polling completion lives in +Polling; timeline ingest in +Timeline.
//

import Foundation
import os.log

extension AgentNetworkEngine {

    // MARK: - Launch / cancel

    /// Create/reuse a session, submit an async prompt, then poll history.
    func launchHeadlessAgent() async throws {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentEngineError.emptyPrompt
        }
        guard !phase.isBusy else {
            throw AgentEngineError.alreadyRunning
        }
        if !socketState.isReady {
            if !wantsRunning { start() }
            try await waitUntilConnected(timeout: 12)
        }

        phase = .launching
        lastError = nil
        result = nil
        pollStatus = .queued
        turnStablePolls = 0
        turnLastFingerprint = nil
        stopPolling()

        do {
            let sid = try await ensureSession()
            activeTaskID = sid

            // Snapshot server history *before* this turn so we do not treat the
            // previous assistant reply as completion for the new prompt.
            let prior = try await api.sessionHistory(id: sid, limit: 200)
            timelineIDsBeforeTurn = Set(
                prior.entries
                    .map(\.id)
                    .filter { !$0.isEmpty }
            )
            // Rebuild timeline from full history (conversation continuity).
            seenTimelineIDs = []
            eventLog = []
            eventSequence = 0
            turnStablePolls = 0
            turnLastFingerprint = nil
            applyHistory(prior, forDisplay: true)

            appendUserCommandEvent(
                taskId: sid,
                prompt: trimmed,
                mode: composerMode,
                modelID: modelID,
                contextPaths: contextPaths
            )

            let body = SessionPromptBody(
                prompt: trimmed,
                model: modelID.isEmpty ? nil : modelID,
                mode: composerMode.rawValue,
                contextPaths: contextPaths.isEmpty ? nil : contextPaths
            )
            let acceptedRemote = try await api.promptSession(id: sid, body: body)
            activeTaskID = acceptedRemote.sessionId
            phase = .processing
            pollStatus = .running
            prompt = ""
            startPolling(sessionId: acceptedRemote.sessionId)
            log.info(
                "session prompt accepted sessionId=\(acceptedRemote.sessionId, privacy: .public) mode=\(acceptedRemote.mode ?? "-", privacy: .public) baselineMsgs=\(self.timelineIDsBeforeTurn.count, privacy: .public)"
            )
        } catch {
            let message = mapError(error)
            phase = .failed(message)
            lastError = message
            stopPolling()
            throw error
        }
    }

    func cancelActiveTask() async {
        guard let sessionId = sessionID ?? activeTaskID else { return }
        do {
            let _: SessionCancelResponse = try await api.cancelSession(id: sessionId)
            phase = .cancelled
            pollStatus = .cancelled
            appendSyntheticEvent(
                taskId: sessionId,
                status: .cancelled,
                stage: .cancelled,
                message: "cancel signal sent"
            )
            stopPolling()
        } catch {
            lastError = mapError(error)
        }
    }
}
