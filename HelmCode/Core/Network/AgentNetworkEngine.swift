//
//  AgentNetworkEngine.swift
//  HelmCode
//
//  WebSocket JSON-RPC client for runner-core `/v1/agent`.
//  Marshals `agent/run`, streams `agent/progress` / `agent/done`, polls `agent/status`.
//  Wire types / socket state: AgentJSONRPC.swift · UI models: AgentModels.swift
//

import Combine
import Foundation
import os.log

/// Observable agent controller state machine + live timeline.
@MainActor
final class AgentNetworkEngine: ObservableObject {

    // MARK: - Published surface

    @Published private(set) var socketState: AgentSocketState = .disconnected
    @Published private(set) var phase: AgentControllerPhase = .idle
    @Published private(set) var activeTaskID: String?
    @Published private(set) var branch: String?
    @Published private(set) var pollStatus: TaskStatus?
    @Published private(set) var events: [TaskProgressEvent] = []
    @Published private(set) var eventLog: [EventLog] = []
    @Published private(set) var result: AgentResult?
    @Published private(set) var lastError: String?
    @Published private(set) var accepted: AgentRunAccepted?

    /// Surgical context paths selected from the VFS tree (relative).
    @Published var contextPaths: [String] = []
    /// Composer prompt bound by AgentCommandPanel.
    @Published var prompt: String = ""
    /// Optional overrides surfaced in the command panel.
    @Published var baseBranch: String = "main"
    @Published var testCommand: String = ""
    @Published var maxCycles: Int = 3
    /// Cursor-style composer mode (agent / plan / ask).
    @Published var composerMode: AgentComposerMode = .agent
    /// Selected model id (sent as task metadata).
    @Published var modelID: String = AgentModelOption.defaultID

    var baseURLString: String {
        didSet {
            if baseURLString != oldValue, wantsRunning {
                reconnectNow(reason: "base URL changed")
            }
        }
    }

    var apiToken: String {
        didSet {
            if apiToken != oldValue, wantsRunning {
                reconnectNow(reason: "token changed")
            }
        }
    }

    // MARK: - Internals

    private let session: URLSession
    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?

    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var wantsRunning = false
    private var reconnectAttempt = 0
    private var eventSequence = 0

    private let requestTimeout: TimeInterval
    private let pollInterval: TimeInterval
    private let heartbeatInterval: TimeInterval
    private let log = Logger(subsystem: "com.helmcode.HelmCode", category: "Agent")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    init(
        // Host port published by compose (container still listens on 8080).
        baseURLString: String = "http://127.0.0.1:18080",
        apiToken: String = "",
        requestTimeout: TimeInterval = 45,
        pollInterval: TimeInterval = 1.0,
        heartbeatInterval: TimeInterval = 20,
        session: URLSession = .shared
    ) {
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.requestTimeout = requestTimeout
        self.pollInterval = pollInterval
        self.heartbeatInterval = heartbeatInterval
        self.session = session
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
        stopPolling()
        tearDownSocket(reason: "stopped")
        socketState = .disconnected
        if !phase.isBusy {
            phase = .idle
        }
    }

    /// Copy credentials only — does **not** open the socket (project activation owns lifecycle).
    func syncCredentials(from http: HelmCodeNetworkEngine) {
        baseURLString = http.baseURLString
        apiToken = http.apiToken
    }

    /// Bind to the open project's runner and ensure the agent WebSocket is up.
    func bindToProjectRunner(from http: HelmCodeNetworkEngine) {
        syncCredentials(from: http)
        if wantsRunning {
            // URL/token didSet already reconnects when values change.
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
        // Keep historical timeline only if a task finished; drop mid-flight noise.
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

    /// Ensure the currently selected editor file is in the surgical table.
    func includeSelectedFile(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        addContextPath(path)
    }

    // MARK: - Launch / cancel

    /// Marshal `agent/run` over the live WebSocket and enter processing layout.
    @discardableResult
    func launchHeadlessAgent(githubToken: String? = nil) async throws -> AgentRunAccepted {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentEngineError.emptyPrompt
        }
        guard !phase.isBusy else {
            throw AgentEngineError.alreadyRunning
        }
        if !(socketState.isReady && webSocket != nil) {
            // Attempt a quick connect if the socket is cold.
            if !wantsRunning { start() }
            try await waitUntilConnected(timeout: 8)
        }

        let params = AgentRunParams.launch(
            prompt: trimmed,
            contextPaths: contextPaths,
            baseBranch: baseBranch.trimmingCharacters(in: .whitespacesAndNewlines),
            testCommand: testCommand.trimmingCharacters(in: .whitespacesAndNewlines),
            githubToken: githubToken,
            maxCycles: max(1, min(maxCycles, 10)),
            mode: composerMode,
            modelID: modelID
        )

        phase = .launching
        lastError = nil
        result = nil
        events = []
        eventLog = []
        eventSequence = 0
        accepted = nil
        activeTaskID = params.taskId
        pollStatus = .queued
        branch = "aero-agent/\(params.taskId)"

        do {
            let acceptedResult: AgentRunAccepted = try await call(
                method: "agent/run",
                params: params
            )
            accepted = acceptedResult
            activeTaskID = acceptedResult.taskId
            branch = acceptedResult.branch
            phase = .processing
            startPolling(taskId: acceptedResult.taskId)
            log.info("agent/run accepted taskId=\(acceptedResult.taskId, privacy: .public) branch=\(acceptedResult.branch, privacy: .public)")
            return acceptedResult
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            lastError = message
            stopPolling()
            throw error
        }
    }

    func cancelActiveTask() async {
        guard let taskId = activeTaskID else { return }
        do {
            struct CancelParams: Encodable { let taskId: String }
            struct CancelResult: Decodable {
                let taskId: String
                let status: String
                let message: String?
            }
            let _: CancelResult = try await call(
                method: "agent/cancel",
                params: CancelParams(taskId: taskId)
            )
            phase = .cancelled
            pollStatus = .cancelled
            appendSyntheticEvent(
                taskId: taskId,
                status: .cancelled,
                stage: .cancelled,
                message: "cancel signal sent"
            )
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func resetSession() {
        stopPolling()
        phase = socketState.isReady ? .ready : .idle
        activeTaskID = nil
        pollStatus = nil
        events = []
        eventLog = []
        result = nil
        lastError = nil
        accepted = nil
        branch = nil
        eventSequence = 0
    }

    // MARK: - JSON-RPC call

    func call<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        guard let socket = webSocket else {
            throw AgentEngineError.notConnected
        }

        let id = nextRequestID
        nextRequestID += 1

        let payload: String
        do {
            let data = try encoder.encode(AgentJSONRPCRequest(id: id, method: method, params: params))
            guard let text = String(data: data, encoding: .utf8) else {
                throw AgentEngineError.encoding("Unable to UTF-8 encode request")
            }
            payload = text
        } catch let error as AgentEngineError {
            throw error
        } catch {
            throw AgentEngineError.encoding(error.localizedDescription)
        }

        let timeoutNs = UInt64(requestTimeout * 1_000_000_000)
        let responseData: Data = try await withCheckedThrowingContinuation { cont in
            pending[id] = cont
            socket.send(.string(payload)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    guard let self, let pending = self.pending.removeValue(forKey: id) else { return }
                    pending.resume(throwing: error)
                }
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: timeoutNs)
                guard let self, let pending = self.pending.removeValue(forKey: id) else { return }
                pending.resume(throwing: AgentEngineError.timeout)
                self.log.error("Agent RPC timed out id=\(id) method=\(method, privacy: .public)")
                if self.wantsRunning {
                    self.scheduleReconnect(reason: "request timeout")
                }
            }
        }

        if let envelope = try? decoder.decode(AgentJSONRPCInbound.self, from: responseData),
           let error = envelope.error {
            throw AgentEngineError.rpc(code: error.code, message: error.message)
        }

        do {
            return try decoder.decode(AgentJSONRPCResultBox<R>.self, from: responseData).result
        } catch {
            throw AgentEngineError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Connect

    private func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket(reason: "reconnect")

        guard let url = RunnerURL.webSocketAgentURL(fromBase: baseURLString) else {
            socketState = .failed("Invalid base URL")
            lastError = AgentEngineError.invalidURL.localizedDescription
            if !phase.isBusy {
                phase = .failed(AgentEngineError.invalidURL.localizedDescription)
            }
            return
        }

        socketState = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        if !phase.isBusy {
            phase = .connecting
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()
        log.info("Agent WS connecting \(url.absoluteString, privacy: .public)")

        startReceiveLoop()
        startHeartbeat()

        // Real handshake: only mark ready after `agent/list` succeeds over the socket.
        Task { @MainActor [weak self] in
            guard let self, self.wantsRunning else { return }
            // Brief yield so the upgrade can complete before the first RPC.
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard self.webSocket === task else { return }
            do {
                try await self.probeHandshake()
                guard self.webSocket === task, self.wantsRunning else { return }
                self.socketState = .connected
                self.reconnectAttempt = 0
                self.lastError = nil
                // Always leave linking state once the socket is proven live,
                // unless a real agent task is already running.
                if !self.phase.isBusy {
                    self.phase = .ready
                }
                self.log.info("Agent WS ready \(url.absoluteString, privacy: .public)")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.log.error("Agent handshake failed: \(message, privacy: .public)")
                self.lastError = message
                if self.wantsRunning {
                    self.scheduleReconnect(reason: message)
                } else {
                    self.socketState = .failed(message)
                    if !self.phase.isBusy {
                        self.phase = .failed(message)
                    }
                }
            }
        }
    }

    /// Lightweight RPC used as a connection liveness probe.
    private func probeHandshake() async throws {
        struct EmptyParams: Encodable {}
        struct ListResult: Decodable {
            let activeTasks: Int?
            let tasks: [JSONValue]?
        }
        let _: ListResult = try await call(method: "agent/list", params: EmptyParams())
    }

    private func reconnectNow(reason: String) {
        log.info("Agent reconnect: \(reason, privacy: .public)")
        scheduleReconnect(reason: reason)
    }

    private func scheduleReconnect(reason: String) {
        guard wantsRunning else { return }
        reconnectTask?.cancel()
        tearDownSocket(reason: reason)
        reconnectAttempt += 1
        lastError = reason
        socketState = .reconnecting(attempt: reconnectAttempt)
        // Keep phase honest while we are not mid-task.
        if !phase.isBusy {
            phase = .connecting
        }
        // Cap backoff so a dead runner does not thrash the UI forever at full speed.
        let delay = min(pow(1.6, Double(min(reconnectAttempt, 8))), 20.0)
        log.info("Agent reconnect in \(delay, privacy: .public)s — \(reason, privacy: .public)")
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.wantsRunning, !Task.isCancelled else { return }
            self.connect()
        }
    }

    private func tearDownSocket(reason: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        receiveTask?.cancel()
        receiveTask = nil
        failPending(with: AgentEngineError.closed(reason))
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    private func failPending(with error: Error) {
        let pendingCopy = pending
        pending.removeAll()
        for (_, cont) in pendingCopy {
            cont.resume(throwing: error)
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let socket = self.webSocket
                socket?.sendPing { [weak self] error in
                    guard let error else { return }
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.log.error("Agent ping failed: \(error.localizedDescription, privacy: .public)")
                        if self.wantsRunning {
                            self.scheduleReconnect(reason: "ping failed")
                        }
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    // MARK: - Receive loop

    private func startReceiveLoop() {
        receiveTask?.cancel()
        let task = webSocket
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let socket = await MainActor.run(body: { self.webSocket }), socket === task else {
                    break
                }
                do {
                    let message = try await socket.receive()
                    await self.handle(message: message)
                } catch {
                    await MainActor.run {
                        self.log.error("Agent receive error: \(error.localizedDescription, privacy: .public)")
                        self.failPending(with: error)
                        if self.wantsRunning {
                            self.scheduleReconnect(reason: error.localizedDescription)
                        } else {
                            self.socketState = .disconnected
                        }
                    }
                    break
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) async {
        let data: Data
        switch message {
        case .data(let value):
            data = value
        case .string(let text):
            data = Data(text.utf8)
        @unknown default:
            return
        }

        let inbound: AgentJSONRPCInbound
        do {
            inbound = try decoder.decode(AgentJSONRPCInbound.self, from: data)
        } catch {
            log.error("Agent inbound decode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if let id = inbound.id?.intValue {
            if let cont = pending.removeValue(forKey: id) {
                cont.resume(returning: data)
            }
            return
        }

        if let method = inbound.method {
            let params = inbound.params
            let raw = data
            Task { @MainActor [weak self] in
                await self?.handleNotification(method: method, params: params, raw: raw)
            }
        }
    }

    private func handleNotification(method: String, params: JSONValue?, raw: Data) async {
        switch method {
        case "agent/progress":
            if let event = decodeParams(TaskProgressEvent.self, params: params, raw: raw) {
                ingestProgress(event)
            }
        case "agent/done":
            if let done = decodeParams(AgentDoneNotification.self, params: params, raw: raw) {
                applyDone(done)
            }
        default:
            log.debug("Agent notification ignored: \(method, privacy: .public)")
        }
    }

    private func decodeParams<T: Decodable>(_ type: T.Type, params: JSONValue?, raw: Data) -> T? {
        if let params {
            do {
                let encoded = try JSONEncoder().encode(params)
                return try decoder.decode(T.self, from: encoded)
            } catch {
                log.error("Agent notification params decode failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        // Full notification frame: `{ "method": "…", "params": {…} }`
        if let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
           let paramsObj = obj["params"],
           JSONSerialization.isValidJSONObject(paramsObj),
           let paramsData = try? JSONSerialization.data(withJSONObject: paramsObj),
           let value = try? decoder.decode(T.self, from: paramsData) {
            return value
        }
        return nil
    }

    // MARK: - Progress / polling

    private func ingestProgress(_ event: TaskProgressEvent) {
        // Deduplicate by structural id when pushes + polls overlap.
        if events.contains(where: { $0.id == event.id }) {
            return
        }
        events.append(event)
        eventSequence += 1
        let node = EventLog(from: event, sequence: eventSequence)
        eventLog.append(node)
        pollStatus = event.status
        activeTaskID = event.taskId
        if phase == .launching || phase == .ready || phase == .idle {
            phase = .processing
        }
        if event.status.isTerminal {
            // Wait for agent/done or poll result for full AgentResult.
        }
    }

    private func applyDone(_ done: AgentDoneNotification) {
        stopPolling()
        activeTaskID = done.taskId
        if let result = done.result {
            self.result = result
            pollStatus = result.status
            switch result.status {
            case .succeeded:
                phase = .succeeded
            case .cancelled:
                phase = .cancelled
            case .failed:
                phase = .failed(result.error ?? result.summary)
                lastError = result.error ?? result.summary
            default:
                phase = .failed(result.summary)
            }
            branch = result.branch
            return
        }

        let wire = done.status.lowercased()
        switch wire {
        case "success", "succeeded":
            phase = .succeeded
            pollStatus = .succeeded
        case "cancelled":
            phase = .cancelled
            pollStatus = .cancelled
        default:
            let message = done.error ?? "Agent task failed"
            phase = .failed(message)
            pollStatus = .failed
            lastError = message
        }
    }

    private func startPolling(taskId: String) {
        stopPolling()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollStatusOnce(taskId: taskId)
                if self.phase == .succeeded
                    || self.phase == .cancelled
                    || {
                        if case .failed = self.phase { return true }
                        return false
                    }() {
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollStatusOnce(taskId: String) async {
        struct StatusParams: Encodable { let taskId: String }
        do {
            let snap: AgentTaskSnapshot = try await call(
                method: "agent/status",
                params: StatusParams(taskId: taskId)
            )
            applySnapshot(snap)
        } catch {
            // Soft-fail polls; progress notifications remain primary.
            log.debug("agent/status poll soft-fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func applySnapshot(_ snap: AgentTaskSnapshot) {
        activeTaskID = snap.taskId
        pollStatus = snap.status
        branch = snap.branch

        for event in snap.events {
            if !events.contains(where: { $0.id == event.id }) {
                ingestProgress(event)
            }
        }

        if let terminal = snap.result {
            result = terminal
            stopPolling()
            switch terminal.status {
            case .succeeded: phase = .succeeded
            case .cancelled: phase = .cancelled
            case .failed:
                phase = .failed(terminal.error ?? terminal.summary)
                lastError = terminal.error ?? terminal.summary
            default:
                phase = .failed(terminal.summary)
            }
        } else if snap.status.isTerminal {
            stopPolling()
            switch snap.status {
            case .succeeded: phase = .succeeded
            case .cancelled: phase = .cancelled
            case .failed: phase = .failed(lastError ?? "Task failed")
            default: break
            }
        } else if phase.isBusy {
            phase = .processing
        }
    }

    private func appendSyntheticEvent(
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

    private func waitUntilConnected(timeout: TimeInterval) async throws {
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
}
