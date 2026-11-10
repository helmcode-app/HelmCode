//
//  AgentNetworkEngine.swift
//  HelmCode
//
//  Observable agent controller for runner-core `/v1/sessions/*`.
//
//  File map (same type, split by concern):
//    AgentNetworkEngine.swift            — state, lifecycle, context paths, helpers
//    AgentNetworkEngine+Connection.swift — health, reconnect, model catalog
//    AgentNetworkEngine+Sessions.swift   — list / create / select / delete / titles
//    AgentNetworkEngine+Launch.swift     — prompt launch + cancel
//    AgentNetworkEngine+Polling.swift    — history poll + turn completion
//    AgentNetworkEngine+Timeline.swift   — history → EventLog, synthetic rows
//    AgentLinkState.swift                — socket state + engine errors
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
    /// Selected model id (`provider/model`). Empty until harness catalog loads.
    @Published var modelID: String = AgentModelOption.defaultID
    /// Reasoning effort for the next prompt (`thinkLevel` on session prompt).
    @Published var thinkLevel: AgentThinkLevel = .medium
    /// Effort / reasoning levels advertised by the current harness (empty → hide Think UI).
    @Published var availableThinkLevels: [AgentThinkLevel] = []
    /// Thinking on/off for the next prompt when the harness advertises a toggle.
    @Published var thinkingEnabled: Bool = true
    /// Thinking on/off values advertised by the harness (empty → hide Thinking UI).
    @Published var availableThinkingLevels: [AgentThinkLevel] = []
    /// Context window for the next prompt.
    @Published var contextLevel: AgentThinkLevel = AgentThinkLevel(rawValue: "")
    /// Context sizes advertised by the harness (empty → hide Context UI).
    @Published var availableContextLevels: [AgentThinkLevel] = []
    /// Fast inference for the next prompt (`fast` on session prompt).
    @Published var fastMode: Bool = false
    /// Whether the current harness advertises a fast option.
    @Published var supportsFastMode: Bool = false
    /// Live models from GET /v1/sessions/models (current harness only).
    @Published var modelCatalog: [AgentModelOption] = []
    /// Agent sessions for the Cursor-style chat list.
    @Published var sessions: [AgentSessionDTO] = []
    /// Active chat session title (from list / create).
    @Published var sessionTitle: String?
    /// Workspace bound to VFS / terminal / new sessions.
    @Published var workspaceId: String = HelmWorkspace.defaultID
    /// ACP mode ids from the active session (`build`, `plan`, …). Empty until create/select.
    @Published var advertisedModes: [String] = []
    /// Latest ACP `usage_update` for the active session (nil until the runner reports it).
    @Published var sessionUsage: SessionUsage?

    var availableComposerModes: [AgentComposerMode] {
        AgentComposerMode.available(advertised: advertisedModes)
    }

    /// Public id of the active chat (for UI).
    var activeSessionID: String? { sessionID }

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
    /// Live `GET /v1/sessions/events` SSE (usage / config fan-out).
    var eventsTask: Task<Void, Never>?
    var eventSequence = 0
    var sessionID: String?
    var seenTimelineIDs: Set<String> = []
    /// Message ids known **before** the current turn's prompt (server history).
    /// Completion requires a new assistant message id not in this set.
    var timelineIDsBeforeTurn: Set<String> = []
    /// Avoid re-fetching / re-publishing the model list on every reconnect unless forced.
    var modelCatalogLoaded = false
    /// Bumps on each catalog request so slower responses cannot overwrite newer caps.
    var modelCatalogGeneration = 0
    /// Per-model Effort / Thinking / Context / Fast from the last successful probe.
    var modelCapsByID: [String: AgentModelCaps] = [:]
    /// Consecutive stable history fingerprints while waiting for multi-step turns to settle.
    var turnStablePolls = 0
    var turnLastFingerprint: String?
    let pollInterval: TimeInterval
    let log = Logger(subsystem: "com.helmcode.HelmCode", category: "Agent")

    /// Capability snapshot for one model id (Cursor caps are model-dependent).
    struct AgentModelCaps: Equatable, Sendable {
        var thinkLevels: [AgentThinkLevel]
        var thinkingLevels: [AgentThinkLevel]
        var contextLevels: [AgentThinkLevel]
        var context: String?
        var supportsFast: Bool
    }

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
        stopEvents()
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
        clearChatSurface()
        workspaceId = HelmWorkspace.defaultID
        if !phase.isBusy {
            clearContextPaths()
            prompt = ""
        }
    }

    /// Drop active chat + history list so a project switch cannot show the previous workspace.
    func clearChatSurface() {
        stopPolling()
        sessionID = nil
        sessionTitle = nil
        sessions = []
        advertisedModes = []
        sessionUsage = nil
        resetSession()
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

    // MARK: - Session UI reset

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
        sessionUsage = nil
        // Keep sessionID so follow-up prompts reuse the conversation.
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
                if Self.isSessionsConfigError(statusCode: code, message: message) {
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

    /// Permanent config gap — do not reconnect-loop until the user enables `/v1/agent`.
    static func isSessionsConfigError(statusCode: Int, message: String) -> Bool {
        guard statusCode == 503 else { return false }
        let m = message.lowercased()
        return m.contains("disabled")
            || m.contains("put /v1/agent")
            || m.contains("configure via")
    }
}
