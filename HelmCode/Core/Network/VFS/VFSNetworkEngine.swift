//
//  VFSNetworkEngine.swift
//  HelmCode
//
//  Persistent WebSocket tunnel to runner-core `ws://…/v1/vfs` with JSON-RPC 2.0.
//  Heartbeat + auto-reconnect for Stage Manager / network drops.
//

import Combine
import Foundation
import os.log

/// VFS connection state machine + JSON-RPC client for `helm-vfs`.
@MainActor
final class VFSNetworkEngine: ObservableObject {

    // MARK: - Published

    @Published private(set) var connectionState: VFSConnectionState = .disconnected
    @Published private(set) var workspaceRoot: String?
    @Published private(set) var tree: WorkspaceTreeNode?
    @Published private(set) var lastError: String?
    @Published private(set) var lastChange: VFSDidChangeParams?
    /// Path → latest known text (filled by `read` / `write` / selective reload).
    @Published private(set) var fileBuffers: [String: String] = [:]
    /// Bumps when a buffer was refreshed from the server (editor can rebind).
    @Published private(set) var bufferRevision: UInt64 = 0

    // MARK: - Config

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

    /// Optional root override for `vfs/initialize` (nil = server default `MAIN_REPO_PATH`).
    var initializeRoot: String?

    // MARK: - Internals

    private let session: URLSession
    private var webSocket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTimer: Timer?
    private var reconnectTask: Task<Void, Never>?

    private var nextRequestID = 1
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]

    private var wantsRunning = false
    private var reconnectAttempt = 0
    private let requestTimeout: TimeInterval
    private let heartbeatInterval: TimeInterval
    private let log = Logger(subsystem: "com.helmcode.HelmCode", category: "VFS")

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    init(
        baseURLString: String = "http://127.0.0.1:8080",
        apiToken: String = "",
        initializeRoot: String? = nil,
        requestTimeout: TimeInterval = 30,
        heartbeatInterval: TimeInterval = 15,
        session: URLSession = .shared
    ) {
        self.baseURLString = baseURLString
        self.apiToken = apiToken
        self.initializeRoot = initializeRoot
        self.requestTimeout = requestTimeout
        self.heartbeatInterval = heartbeatInterval
        self.session = session
    }

    deinit {
        // Timers/tasks torn down from MainActor stop() when possible.
    }

    // MARK: - Lifecycle

    /// Start (or restart) the VFS tunnel and run `vfs/initialize`.
    func start() {
        wantsRunning = true
        reconnectAttempt = 0
        connect()
    }

    func stop() {
        wantsRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket(reason: "stopped")
        connectionState = .disconnected
    }

    // MARK: - High-level VFS API

    @discardableResult
    func initialize(root: String? = nil) async throws -> VFSInitializeResult {
        let params = VFSInitializeParams(root: root ?? initializeRoot)
        let result: VFSInitializeResult = try await call(method: "vfs/initialize", params: params)
        workspaceRoot = result.root
        let assembled = WorkspaceTreeAssembler.assemble(entries: result.entries, rootPath: result.root)
        tree = assembled
        log.info("vfs/initialize root=\(result.root, privacy: .public) entries=\(result.entries.count)")
        return result
    }

    func read(path: String) async throws -> VFSReadResult {
        let result: VFSReadResult = try await call(
            method: "vfs/read",
            params: VFSPathParams(path: path)
        )
        fileBuffers[result.path] = result.content
        bufferRevision &+= 1
        return result
    }

    @discardableResult
    func write(path: String, content: String) async throws -> VFSWriteResult {
        let result: VFSWriteResult = try await call(
            method: "vfs/write",
            params: VFSWriteParams(path: path, content: content)
        )
        fileBuffers[result.path] = content
        bufferRevision &+= 1
        return result
    }

    func shutdownRemote() async throws {
        struct Empty: Decodable {}
        let _: Empty = try await call(method: "vfs/shutdown", params: VFSEmptyParams())
    }

    /// Cached text if present.
    func cachedContent(for path: String) -> String? {
        fileBuffers[path]
    }

    // MARK: - JSON-RPC

    func call<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        guard let socket = webSocket else {
            throw VFSError.notConnected
        }

        let id = nextRequestID
        nextRequestID += 1

        let payload: String
        do {
            let data = try encoder.encode(VFSJSONRPCRequest(id: id, method: method, params: params))
            guard let text = String(data: data, encoding: .utf8) else {
                throw VFSError.encoding("Unable to UTF-8 encode request")
            }
            payload = text
        } catch let error as VFSError {
            throw error
        } catch {
            throw VFSError.encoding(error.localizedDescription)
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
                pending.resume(throwing: VFSError.timeout)
            }
        }

        if let envelope = try? decoder.decode(VFSJSONRPCInbound.self, from: responseData),
           let error = envelope.error {
            throw VFSError.rpc(code: error.code, message: error.message)
        }

        do {
            return try decoder.decode(VFSJSONRPCResultBox<R>.self, from: responseData).result
        } catch {
            throw VFSError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Connect

    private func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        tearDownSocket(reason: "reconnect")

        guard let url = makeWebSocketURL() else {
            connectionState = .failed("Invalid base URL")
            lastError = VFSError.invalidURL.localizedDescription
            return
        }

        connectionState = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        lastError = nil

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = session.webSocketTask(with: request)
        webSocket = task
        task.resume()
        log.info("VFS connecting \(url.absoluteString, privacy: .public)")

        startReceiveLoop()
        startHeartbeat()

        // Probe: initialize once the socket is up (send may fail until open — retry via receive path / backoff).
        Task { @MainActor [weak self] in
            guard let self, self.wantsRunning else { return }
            // Small delay so the handshake can complete.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard self.webSocket === task else { return }
            do {
                self.connectionState = .connected
                self.reconnectAttempt = 0
                _ = try await self.initialize()
            } catch {
                self.log.error("vfs initialize failed: \(error.localizedDescription, privacy: .public)")
                self.lastError = error.localizedDescription
                self.scheduleReconnect(reason: error.localizedDescription)
            }
        }
    }

    private func makeWebSocketURL() -> URL? {
        RunnerURL.webSocketVFSURL(fromBase: baseURLString)
    }

    // MARK: - Receive

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
                        self.log.error("VFS receive error: \(error.localizedDescription, privacy: .public)")
                        self.failPending(with: error)
                        if self.wantsRunning {
                            self.scheduleReconnect(reason: error.localizedDescription)
                        } else {
                            self.connectionState = .disconnected
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

        let inbound: VFSJSONRPCInbound
        do {
            inbound = try decoder.decode(VFSJSONRPCInbound.self, from: data)
        } catch {
            log.error("VFS inbound decode failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        if inbound.isNotification, let method = inbound.method {
            await handleNotification(method: method, params: inbound.params, raw: data)
            return
        }

        guard let id = inbound.id?.intValue else {
            // Notification without method (ignore) or malformed.
            if let method = inbound.method {
                await handleNotification(method: method, params: inbound.params, raw: data)
            }
            return
        }

        if let cont = pending.removeValue(forKey: id) {
            cont.resume(returning: data)
        }
    }

    private func handleNotification(method: String, params: JSONValue?, raw: Data) async {
        switch method {
        case "vfs/didChange":
            let change: VFSDidChangeParams
            if let params {
                do {
                    let encoded = try JSONEncoder().encode(params)
                    change = try decoder.decode(VFSDidChangeParams.self, from: encoded)
                } catch {
                    log.error("vfs/didChange decode failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            } else {
                // Fallback: decode params from full envelope.
                struct Note: Decodable {
                    let params: VFSDidChangeParams
                }
                guard let note = try? decoder.decode(Note.self, from: raw) else { return }
                change = note.params
            }

            log.info("vfs/didChange \(change.type.rawValue, privacy: .public) \(change.path, privacy: .public)")
            lastChange = change
            await applyDidChange(change)

        default:
            log.debug("VFS notification ignored: \(method, privacy: .public)")
        }
    }

    /// Selective reload: refresh tree on structural change; reload open buffer on write.
    private func applyDidChange(_ change: VFSDidChangeParams) async {
        switch change.type {
        case .write:
            if fileBuffers[change.path] != nil || tree?.find(path: change.path) != nil {
                do {
                    _ = try await read(path: change.path)
                } catch {
                    log.error("selective reload failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case .create, .remove, .rename:
            // Re-scan tree from server.
            do {
                _ = try await initialize(root: workspaceRoot)
                if change.type == .remove {
                    fileBuffers.removeValue(forKey: change.path)
                    bufferRevision &+= 1
                } else if change.type == .create || change.type == .rename {
                    // Best-effort: if we had a buffer, refresh.
                    if fileBuffers[change.path] != nil {
                        _ = try? await read(path: change.path)
                    }
                }
            } catch {
                log.error("tree refresh after didChange failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Heartbeat / reconnect

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sendPing()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func sendPing() {
        guard let webSocket, connectionState.isReady else { return }
        webSocket.sendPing { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.log.error("VFS ping failed: \(error.localizedDescription, privacy: .public)")
                    if self.wantsRunning {
                        self.scheduleReconnect(reason: "ping failed")
                    }
                }
            }
        }
    }

    private func scheduleReconnect(reason: String) {
        guard wantsRunning else { return }
        tearDownSocket(reason: reason)
        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)
        lastError = reason

        let delay = min(30.0, pow(1.6, Double(min(reconnectAttempt, 12))))
        reconnectTask?.cancel()
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.wantsRunning, !Task.isCancelled else { return }
            self.connect()
        }
    }

    private func reconnectNow(reason: String) {
        guard wantsRunning else { return }
        reconnectAttempt = 0
        scheduleReconnect(reason: reason)
    }

    private func tearDownSocket(reason: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        receiveTask?.cancel()
        receiveTask = nil
        webSocket?.cancel(with: .goingAway, reason: reason.data(using: .utf8))
        webSocket = nil
        failPending(with: VFSError.closed(reason))
    }

    private func failPending(with error: Error) {
        let pending = self.pending
        self.pending.removeAll()
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }
}
