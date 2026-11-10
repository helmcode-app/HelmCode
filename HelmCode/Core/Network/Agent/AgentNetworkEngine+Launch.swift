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
    func launchHeadlessAgent(explicitPrompt: String? = nil) async throws {
        let rawPrompt = explicitPrompt ?? prompt
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentEngineError.emptyPrompt
        }
        guard !phase.isBusy else {
            throw AgentEngineError.alreadyRunning
        }

        // Immediately clear prompt text on the engine so the composer is empty and disabled.
        prompt = ""

        // Mark busy before any await so Stop is meaningful during connect/session setup.
        phase = .launching
        lastError = nil
        result = nil
        pollStatus = .queued
        turnStablePolls = 0
        turnLastFingerprint = nil
        stopPolling()

        do {
            if !socketState.isReady {
                if !wantsRunning { start() }
                try await waitUntilConnected(timeout: 12)
                try throwIfLaunchCancelled()
            }

            let sid = try await ensureSession()
            try throwIfLaunchCancelled()
            activeTaskID = sid

            // Snapshot server history *before* this turn so we do not treat the
            // previous assistant reply as completion for the new prompt.
            let prior = try await api.sessionHistory(id: sid, limit: 200)
            try throwIfLaunchCancelled()
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
                contextPaths: contextPaths.isEmpty ? nil : contextPaths,
                thinkLevel: availableThinkLevels.isEmpty ? nil : thinkLevel.rawValue,
                thinking: availableThinkingLevels.isEmpty ? nil : (thinkingEnabled ? "true" : "false"),
                context: availableContextLevels.isEmpty ? nil : contextLevel.rawValue,
                fast: supportsFastMode ? fastMode : nil
            )
            let acceptedRemote = try await api.promptSession(id: sid, body: body)
            try throwIfLaunchCancelled()
            activeTaskID = acceptedRemote.sessionId
            await bindTitleAfterPrompt(trimmed, prior: prior)
            try throwIfLaunchCancelled()
            phase = .processing
            pollStatus = .running
            startPolling(sessionId: acceptedRemote.sessionId)
            log.info(
                "session prompt accepted sessionId=\(acceptedRemote.sessionId, privacy: .public) mode=\(acceptedRemote.mode ?? "-", privacy: .public) baselineMsgs=\(self.timelineIDsBeforeTurn.count, privacy: .public)"
            )
        } catch is CancellationError {
            stopPolling()
            if phase != .cancelled {
                phase = .cancelled
                pollStatus = .cancelled
            }
        } catch {
            // Stop during launch sets `.cancelled` — don't overwrite with `.failed`.
            if phase == .cancelled {
                stopPolling()
                return
            }
            let message = mapError(error)
            phase = .failed(message)
            lastError = message
            stopPolling()
            throw error
        }
    }

    func cancelActiveTask() async {
        // Abort in-flight launch even before session/task IDs exist.
        if sessionID == nil, activeTaskID == nil {
            phase = .cancelled
            pollStatus = .cancelled
            stopPolling()
            return
        }
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

    /// Cooperative cancel for `launchHeadlessAgent` awaits.
    private func throwIfLaunchCancelled() throws {
        if phase == .cancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
}
