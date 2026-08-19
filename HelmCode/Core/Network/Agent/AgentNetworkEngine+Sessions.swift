//
//  AgentNetworkEngine+Sessions.swift
//  HelmCode
//
//  Session list, create/select/delete, and restore helpers.
//  Prompt launch is in +Launch; history poll in +Polling.
//

import Foundation
import os.log

extension AgentNetworkEngine {

    // MARK: - Session list (Cursor-style)

    /// Refresh `sessions` from the runner (newest first).
    func refreshSessionList() async {
        do {
            let list = try await api.listSessions()
            sessions = list.sorted { sessionSortKey($0) > sessionSortKey($1) }
            if let sid = sessionID {
                let listed = list.first(where: { $0.id == sid })?.title
                sessionTitle = SessionChatTitle.coalesce(listed, sessionTitle)
            }
        } catch {
            log.debug("listSessions soft-fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Start a fresh chat (new agent session).
    func startNewChat() async {
        guard !phase.isBusy else { return }
        stopPolling()
        sessionID = nil
        sessionTitle = nil
        resetSession()
        do {
            let session = try await api.createSession(
                title: nil,
                workspaceId: workspaceId
            )
            sessionID = session.id
            sessionTitle = session.title ?? SessionChatTitle.placeholder
            activeTaskID = session.id
            applySessionMeta(session)
            await refreshSessionList()
            log.info("new chat sessionId=\(session.id, privacy: .public)")
        } catch {
            lastError = mapError(error)
            phase = .failed(mapError(error))
        }
    }

    /// Switch to an existing session and load its timeline.
    func selectSession(id: String) async {
        guard !phase.isBusy else { return }
        guard id != sessionID else { return }
        stopPolling()
        sessionID = id
        result = nil
        lastError = nil
        pollStatus = nil
        eventLog = []
        eventSequence = 0
        seenTimelineIDs = []
        timelineIDsBeforeTurn = []
        activeTaskID = id
        sessionTitle = sessions.first(where: { $0.id == id })?.title
        sessionUsage = nil
        if let listed = sessions.first(where: { $0.id == id }) {
            applySessionMeta(listed)
        }
        do {
            let history = try await api.sessionHistory(id: id, limit: 200)
            applyHistory(history, forDisplay: true)
            settleIdleAfterRestore()
            await refreshSessionList()
        } catch {
            lastError = mapError(error)
        }
    }

    /// Delete a chat from history.
    func deleteSession(id: String) async {
        guard !phase.isBusy else { return }
        let wasActive = sessionID == id || activeTaskID == id
        do {
            _ = try await api.deleteSession(id: id)
            sessions.removeAll { $0.id == id }
            if wasActive {
                sessionID = nil
                sessionTitle = nil
                resetSession()
            }
            await refreshSessionList()
            log.info("deleted sessionId=\(id, privacy: .public)")
        } catch {
            lastError = mapError(error)
        }
    }

    // MARK: - Session binding

    func ensureSession() async throws -> String {
        if let sessionID {
            return sessionID
        }
        // Prefer resuming a session that already has messages (skip empty shells).
        if let existing = await findLatestNonEmptySessionID() {
            sessionID = existing
            return existing
        }
        let session = try await api.createSession(
            title: nil,
            workspaceId: workspaceId
        )
        sessionID = session.id
        applySessionMeta(session)
        return session.id
    }

    /// After health OK: bind to the newest session that has real timeline text.
    func restoreSessionTimelineIfNeeded() async {
        guard !phase.isBusy else { return }
        do {
            if let sid = sessionID {
                let history = try await api.sessionHistory(id: sid, limit: 200)
                if historyHasContent(history) {
                    applyHistory(history, forDisplay: true)
                    settleIdleAfterRestore()
                    return
                }
            }
            guard let sid = await findLatestNonEmptySessionID() else {
                settleIdleAfterRestore()
                return
            }
            sessionID = sid
            activeTaskID = sid
            let history = try await api.sessionHistory(id: sid, limit: 200)
            applyHistory(history, forDisplay: true)
            settleIdleAfterRestore()
            log.info("restored session timeline sessionId=\(sid, privacy: .public)")
        } catch {
            log.debug("session restore soft-fail: \(error.localizedDescription, privacy: .public)")
            settleIdleAfterRestore()
        }
    }

    /// Re-open must not leave UI stuck on Running from history ingest side-effects.
    func settleIdleAfterRestore() {
        stopPolling()
        pollStatus = nil
        result = nil
        if !phase.isBusy {
            phase = socketState.isReady ? .ready : .idle
        }
    }

    func findLatestNonEmptySessionID() async -> String? {
        do {
            let sessions = try await api.listSessions()
            // Prefer most recently updated (string timestamps may be millis or ISO).
            let ordered = sessions.sorted { a, b in
                sessionSortKey(a) > sessionSortKey(b)
            }
            for session in ordered.prefix(12) {
                let history = try await api.sessionHistory(id: session.id, limit: 50)
                if historyHasContent(history) {
                    return session.id
                }
            }
        } catch {
            log.debug("listSessions soft-fail: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    func historyHasContent(_ history: SessionHistoryEnvelope) -> Bool {
        history.entries.contains {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func sessionSortKey(_ session: AgentSessionDTO) -> String {
        session.updatedAt ?? session.createdAt ?? session.id
    }

    func applySessionMeta(_ session: AgentSessionDTO) {
        if let title = SessionChatTitle.coalesce(session.title, sessionTitle) {
            sessionTitle = title
        }
        upsertListedSession(session)
        if let modes = session.modes {
            advertisedModes = modes
        }
        if let wid = session.workspaceId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !wid.isEmpty {
            workspaceId = wid
        }
        if let usage = session.usage {
            sessionUsage = usage
        }
        if !availableComposerModes.contains(composerMode) {
            composerMode = .agent
        }
    }

    /// First user prompt becomes the chat name while the title is still a placeholder.
    func adoptGeneratedTitleIfNeeded(from prompt: String) {
        guard SessionChatTitle.isPlaceholder(sessionTitle) else { return }
        applyGeneratedTitle(SessionChatTitle.fromUserPrompt(prompt))
    }

    func bindTitleAfterPrompt(_ prompt: String, prior: SessionHistoryEnvelope) async {
        if !prior.entries.contains(where: \.isUserText) {
            adoptGeneratedTitleIfNeeded(from: prompt)
        }
        await refreshSessionList()
    }

    private func applyGeneratedTitle(_ title: String) {
        sessionTitle = title
        if let sid = sessionID ?? activeTaskID,
           let idx = sessions.firstIndex(where: { $0.id == sid }) {
            sessions[idx].title = title
        }
    }

    private func upsertListedSession(_ session: AgentSessionDTO) {
        var next = session
        if SessionChatTitle.isPlaceholder(next.title),
           let existing = sessions.first(where: { $0.id == session.id })?.title,
           !SessionChatTitle.isPlaceholder(existing) {
            next.title = existing
        }
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = next
        }
    }

    /// Bind to the runner's default workspace (VFS / terminal follow this id).
    func refreshWorkspaces() async {
        do {
            let envelope = try await api.listWorkspaces()
            let id = (envelope.defaultWorkspaceId ?? HelmWorkspace.defaultID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty {
                workspaceId = id
            }
        } catch {
            log.debug("listWorkspaces soft-fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rewind to a user-message checkpoint (chat + files by default).
    func rewindToMessage(_ messageId: String, restore: SessionRewindRestore = .both) async {
        guard !phase.isBusy else { return }
        guard let sid = sessionID else { return }
        do {
            let result = try await api.rewindSession(
                id: sid,
                messageId: messageId,
                restore: restore
            )
            stopPolling()
            seenTimelineIDs = []
            eventLog = []
            eventSequence = 0
            timelineIDsBeforeTurn = []
            applyHistory(
                SessionHistoryEnvelope(
                    sessionId: result.sessionId,
                    session: result.session,
                    entries: result.entries
                ),
                forDisplay: true
            )
            prompt = result.prompt
            settleIdleAfterRestore()
            await refreshSessionList()
            log.info(
                "rewound sessionId=\(result.sessionId, privacy: .public) messageId=\(result.messageId, privacy: .public) restore=\(result.restore.rawValue, privacy: .public) files=\(result.filesRestored, privacy: .public)"
            )
        } catch {
            lastError = mapError(error)
        }
    }
}
