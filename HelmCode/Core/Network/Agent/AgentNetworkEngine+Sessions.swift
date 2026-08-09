//
//  AgentNetworkEngine+Sessions.swift
//  HelmCode
//
//  Session list, create/select/delete, revert/unrevert, and restore helpers.
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
                sessionTitle = list.first(where: { $0.id == sid })?.title
            }
        } catch {
            log.debug("listSessions soft-fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Start a fresh chat (new OpenCode session).
    func startNewChat() async {
        guard !phase.isBusy else { return }
        stopPolling()
        sessionID = nil
        sessionTitle = nil
        canUnrevert = false
        resetSession()
        do {
            let session = try await api.createSession(title: "New chat")
            sessionID = session.id
            sessionTitle = session.title ?? "New chat"
            activeTaskID = session.id
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
        canUnrevert = false
        result = nil
        lastError = nil
        pollStatus = nil
        eventLog = []
        eventSequence = 0
        seenTimelineIDs = []
        timelineIDsBeforeTurn = []
        activeTaskID = id
        sessionTitle = sessions.first(where: { $0.id == id })?.title
        do {
            let history = try await api.sessionHistory(id: id, limit: 200)
            applyHistory(history, forDisplay: true)
            settleIdleAfterRestore()
            await refreshSessionList()
        } catch {
            lastError = mapError(error)
        }
    }

    /// Delete a chat from history (OpenCode session delete).
    func deleteSession(id: String) async {
        guard !phase.isBusy else { return }
        let wasActive = sessionID == id || activeTaskID == id
        do {
            _ = try await api.deleteSession(id: id)
            sessions.removeAll { $0.id == id }
            if wasActive {
                sessionID = nil
                sessionTitle = nil
                canUnrevert = false
                resetSession()
            }
            await refreshSessionList()
            log.info("deleted sessionId=\(id, privacy: .public)")
        } catch {
            lastError = mapError(error)
        }
    }

    /// Roll back workspace + chat to a message (`msg_…` id from timeline detail).
    ///
    /// Cursor-style restore:
    /// 1. Capture that user message → put it back in the composer
    /// 2. OpenCode revert (file + server history effects)
    /// 3. Drop that message and every timeline row after it locally
    func revertToMessage(messageId: String) async {
        guard let sid = sessionID ?? activeTaskID else { return }
        guard !phase.isBusy else { return }
        let mid = messageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mid.hasPrefix("msg") else {
            lastError = "Cannot revert: missing message id"
            return
        }

        // Snapshot prompt text before server history changes.
        let restorePrompt = promptTextForRestore(messageId: mid)

        do {
            _ = try await api.revertSession(id: sid, messageId: mid)
            canUnrevert = true
            result = nil
            lastError = nil
            pollStatus = nil
            stopPolling()

            // Rebuild from server, then ensure the restored message + later rows are gone.
            seenTimelineIDs = []
            eventLog = []
            eventSequence = 0
            timelineIDsBeforeTurn = []
            let history = try await api.sessionHistory(id: sid, limit: 200)
            applyHistory(history, forDisplay: true)
            trimTimelineFromMessage(messageId: mid, inclusive: true)

            // Composer gets the restored user text for re-send / edit.
            if let restorePrompt, !restorePrompt.isEmpty {
                prompt = restorePrompt
            }

            settleIdleAfterRestore()
            await refreshSessionList()
            log.info("reverted sessionId=\(sid, privacy: .public) messageId=\(mid, privacy: .public)")
        } catch {
            lastError = mapError(error)
            phase = .failed(mapError(error))
        }
    }

    /// Undo the last revert (OpenCode unrevert).
    func unrevertLast() async {
        guard let sid = sessionID ?? activeTaskID else { return }
        guard !phase.isBusy else { return }
        do {
            _ = try await api.unrevertSession(id: sid)
            canUnrevert = false
            seenTimelineIDs = []
            eventLog = []
            eventSequence = 0
            let history = try await api.sessionHistory(id: sid, limit: 200)
            applyHistory(history, forDisplay: true)
            settleIdleAfterRestore()
            await refreshSessionList()
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
        let session = try await api.createSession(title: "HelmCode")
        sessionID = session.id
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

    // MARK: - Revert helpers

    /// Plain user prompt for a timeline id (strips Context: chrome).
    func promptTextForRestore(messageId: String) -> String? {
        guard let entry = eventLog.first(where: {
            $0.stage == .userCommand
                && $0.detail?["timelineId"]?.stringValue == messageId
        }) else { return nil }
        if let raw = entry.detail?["prompt"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return AgentTimelineBuilders.normalizeUserPrompt(entry.message)
    }

    /// Drop `messageId` (optional) and every eventLog row after it.
    func trimTimelineFromMessage(messageId: String, inclusive: Bool) {
        guard let idx = eventLog.firstIndex(where: {
            $0.detail?["timelineId"]?.stringValue == messageId
        }) else {
            // Server already removed it; still drop any rows after the last kept user turn
            // that might be orphan agent fragments with no ids.
            return
        }
        let cut = inclusive ? idx : eventLog.index(after: idx)
        guard cut <= eventLog.endIndex else { return }
        let kept = Array(eventLog[..<cut])
        let removedIDs = Set(
            eventLog[cut...].compactMap { $0.detail?["timelineId"]?.stringValue }
        )
        // Also remove the cut message id when inclusive.
        var dropIDs = removedIDs
        if inclusive {
            dropIDs.insert(messageId)
        }

        eventLog = kept
        seenTimelineIDs.subtract(dropIDs)
        timelineIDsBeforeTurn = Set(
            eventLog.compactMap { $0.detail?["timelineId"]?.stringValue }
                .filter { !$0.isEmpty }
        )
        eventSequence = eventLog.count
        phase = socketState.isReady ? .ready : .idle
        result = nil
        pollStatus = nil
    }
}
