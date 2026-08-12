//
//  AgentNetworkEngine.swift
//  HelmCode
//
//  Observable agent controller for runner-core `/v1/sessions/*`.
//  Connection, session list, prompt launch, and history polling live in extensions.
//

import Combine
import Foundation
import os.log

/// Observable agent controller state machine + live timeline.
@MainActor
final class AgentNetworkEngine: ObservableObject {

    // MARK: - Published surface
    //
    // Setters are internal (not private(set)) so file-split extensions can update
    // state. Call sites outside AgentNetworkEngine should treat these as read-only.

    @Published var socketState: AgentSocketState = .disconnected
    @Published var phase: AgentControllerPhase = .idle
    @Published var activeTaskID: String?
    @Published var pollStatus: TaskStatus?
    @Published var eventLog: [EventLog] = []
    @Published var result: AgentResult?
    @Published var lastError: String?

    /// Surgical context paths selected from the VFS tree (relative).
    @Published var contextPaths: [String] = []
    /// Composer prompt bound by AgentCommandPanel.
    @Published var prompt: String = ""
    /// Preferred git branch label in the composer chip (UI only; not sent on session prompt).
    @Published var baseBranch: String = "main"
    /// Cursor-style composer mode (agent / plan / ask).
    @Published var composerMode: AgentComposerMode = .agent
    /// Selected model id (`provider/model`, e.g. opencode/big-pickle).
    @Published var modelID: String = AgentModelOption.defaultID
    /// Live models for connected OpenCode providers (from GET /v1/sessions/models).
    @Published var modelCatalog: [AgentModelOption] = AgentModelOption.fallbackCatalog
    /// OpenCode sessions for the Cursor-style chat list.
    @Published var sessions: [AgentSessionDTO] = []
    /// Active chat session title (from list / create).
    @Published var sessionTitle: String?
    /// True after a revert while unrevert is still available.
    @Published var canUnrevert = false

    /// Public id of the active chat (for UI).
    var activeSessionID: String? { sessionID }

    /// Message ids dropped by Restore (OpenCode may still return them in history).
    /// Filtered out on every history apply until unrevert / new chat / switch session.
    var suppressedTimelineIDs: Set<String> = []

    // MARK: - Internals (shared across extensions)

    var baseURLString: String {
        didSet {
            api.baseURLString = baseURLString
            if baseURLString != oldValue, wantsRunning {
                reconnectNow(reason: "base URL changed")
            }
        }
    }

    var apiToken: String {
        didSet {
            api.apiToken = apiToken
            if apiToken != oldValue, wantsRunning {
                reconnectNow(reason: "token changed")
            }
        }
    }

    var api: RunnerCoreAPIClient
    var wantsRunning = false
    var reconnectAttempt = 0
    var reconnectTask: Task<Void, Never>?
    var healthTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var eventSequence = 0
    var sessionID: String?
    var seenTimelineIDs: Set<String> = []
    /// Message ids known **before** the current turn's prompt (server history).
    /// Completion requires a new assistant message id not in this set.
    var timelineIDsBeforeTurn: Set<String> = []
    /// Avoid re-fetching / re-publishing the model list on every reconnect unless forced.
    var modelCatalogLoaded = false
    /// Consecutive stable history fingerprints while waiting for multi-step turns to settle.
    var turnStablePolls = 0
    var turnLastFingerprint: String?
    let pollInterval: TimeInterval
    let log = Logger(subsystem: "com.helmcode.HelmCode", category: "Agent")

    init(
        baseURLString: String = "http://127.0.0.1:18080",
        apiToken: String = "",
        pollInterval: TimeInterval = 1.0,
        session: URLSession = .shared
    ) {
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.pollInterval = pollInterval
        self.api = RunnerCoreAPIClient(
            baseURLString: baseURLString,
            apiToken: apiToken,
            session: session
        )
    }

    // MARK: - Lifecycle

    func start() {
        wantsRunning = true
        reconnectAttempt = 0
        connect()
    }

    func stop() {
        wantsRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        healthTask?.cancel()
        healthTask = nil
        stopPolling()
        socketState = .disconnected
        if !phase.isBusy {
            phase = .idle
        }
    }

    /// Copy credentials only — does **not** open the link (project activation owns lifecycle).
    func syncCredentials(from http: HelmCodeNetworkEngine) {
        baseURLString = http.baseURLString
        apiToken = http.apiToken
    }

    /// Bind to the open project's runner and ensure sessions health is green.
    func bindToProjectRunner(from http: HelmCodeNetworkEngine) {
        syncCredentials(from: http)
        if wantsRunning {
            if !socketState.isReady {
                start()
            }
        } else {
            start()
        }
    }

    /// Project closed / no runner — tear down agent link and clear transient task UI state.
    func detachFromProject() {
        stop()
        sessionID = nil
        if !phase.isBusy {
            resetSession()
            clearContextPaths()
            prompt = ""
        }
    }

    // MARK: - Context paths

    func addContextPath(_ path: String) {
        let normalized = VFSPath.normalize(path)
        guard !normalized.isEmpty else { return }
        guard !contextPaths.contains(where: { VFSPath.matches($0, normalized) }) else { return }
        contextPaths.append(normalized)
    }

    func removeContextPath(_ path: String) {
        contextPaths.removeAll { VFSPath.matches($0, path) }
    }

    func clearContextPaths() {
        contextPaths.removeAll()
    }

    func includeSelectedFile(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        addContextPath(path)
    }

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
            let _: SessionAbortResponse = try await api.abortSession(id: sessionId)
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

    func resetSession() {
        stopPolling()
        phase = socketState.isReady ? .ready : .idle
        activeTaskID = nil
        pollStatus = nil
        eventLog = []
        result = nil
        lastError = nil
        eventSequence = 0
        seenTimelineIDs = []
        timelineIDsBeforeTurn = []
        // Keep sessionID so follow-up prompts reuse the conversation.
        // Note: suppressedTimelineIDs is only cleared on new chat / switch / unrevert.
    }

    // MARK: - Shared helpers

    func waitUntilConnected(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if socketState.isReady { return }
            if case .failed(let msg) = socketState {
                throw AgentEngineError.closed(msg)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        throw AgentEngineError.notConnected
    }

    func mapError(_ error: Error) -> String {
        if let helm = error as? HelmNetworkError {
            switch helm {
            case .http(let code, let message):
                if code == 503, message.localizedCaseInsensitiveContains("disabled") {
                    return AgentEngineError.sessionsDisabled.localizedDescription
                }
                return "HTTP \(code): \(message)"
            default:
                return helm.localizedDescription
            }
        }
        if let agent = error as? AgentEngineError {
            return agent.localizedDescription
        }
        return error.localizedDescription
    }
}
