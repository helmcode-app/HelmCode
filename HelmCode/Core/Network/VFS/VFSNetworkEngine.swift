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
    /// Display name from `vfs/initialize` (git remote / env), not mount basename.
    @Published private(set) var workspaceName: String?
    /// Git origin display string from `vfs/initialize` (not container path).
    @Published private(set) var workspaceRemote: String?
    /// Current HEAD branch from `vfs/initialize` (empty when detached / unknown).
    @Published private(set) var workspaceBranch: String?
    @Published private(set) var tree: WorkspaceNode?
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
        clearWorkspaceSnapshot()
        connectionState = .disconnected
    }

    // MARK: - High-level VFS API

    @discardableResult
    func initialize(root: String? = nil) async throws -> VFSInitializeResult {
        let params = VFSInitializeParams(root: root ?? initializeRoot)
        let result: VFSInitializeResult = try await call(method: "vfs/initialize", params: params)
        applyInitializeResult(result)
        log.info(
            "vfs/initialize root=\(result.root, privacy: .public) name=\(self.workspaceName ?? "—", privacy: .public) remote=\(self.workspaceRemote ?? "—", privacy: .public) branch=\(self.workspaceBranch ?? "—", privacy: .public) entries=\(result.entries.count)"
        )
        return result
    }

    /// Apply initialize payload to published workspace fields (name / remote / branch / tree).
    private func applyInitializeResult(_ result: VFSInitializeResult) {
        workspaceRoot = result.root
        let trimmed = result.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        workspaceName = trimmed.isEmpty ? nil : trimmed
        let remoteTrimmed = result.remote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        workspaceRemote = remoteTrimmed.isEmpty ? nil : remoteTrimmed
        // Prefer explicit branch; never leave a stale branch from a prior connection.
        let branchTrimmed = result.branch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        workspaceBranch = branchTrimmed.isEmpty ? nil : branchTrimmed
        let assembled = WorkspaceTreeAssembler.assemble(
            entries: result.entries,
            rootPath: result.root,
            rootName: workspaceName
        )
        // Force a publish even when the tree content is structurally equal (same files).
        tree = nil
        tree = assembled
    }

    private func clearWorkspaceSnapshot() {
        workspaceRoot = nil
        workspaceName = nil
        workspaceRemote = nil
        workspaceBranch = nil
        tree = nil
    }

    /// Prefer `readStreaming` / `VFSStreamEngine` for unknown or large sizes.
    /// Falls back to chunked assembly when the server rejects full `vfs/read`.
    func read(path: String) async throws -> VFSReadResult {
        do {
            let result: VFSReadResult = try await call(
                method: "vfs/read",
                params: VFSPathParams(path: path)
            )
            fileBuffers[path] = result.content
            fileBuffers[result.path] = result.content
            bufferRevision &+= 1
            return result
        } catch let error as VFSError {
            // Server: file too large for vfs/read → stream chunks.
            if case .rpc(_, let message) = error,
               message.localizedCaseInsensitiveContains("read_chunk")
                || message.localizedCaseInsensitiveContains("too large") {
                let text = try await readStreaming(path: path)
                return VFSReadResult(path: path, content: text, size: text.utf8.count)
            }
            throw error
        }
    }

    @discardableResult
    func write(path: String, content: String) async throws -> VFSWriteResult {
        let result: VFSWriteResult = try await call(
            method: "vfs/write",
            params: VFSWriteParams(path: path, content: content)
        )
        fileBuffers[path] = content
        fileBuffers[result.path] = content
        bufferRevision &+= 1
        return result
    }

    func shutdownRemote() async throws {
        struct Empty: Decodable {}
        let _: Empty = try await call(method: "vfs/shutdown", params: VFSEmptyParams())
    }

    /// Cached text if present (exact key or slash-normalized match).
    func cachedContent(for path: String) -> String? {
        if let hit = fileBuffers[path] { return hit }
        let normalized = VFSPath.normalize(path)
        if let hit = fileBuffers[normalized] { return hit }
        for (key, value) in fileBuffers where VFSPath.matches(key, path) {
            return value
        }
        return nil
    }

    /// Publish assembled stream content into the buffer map (no network I/O).
    func cacheContent(_ content: String, for path: String) {
        fileBuffers[path] = content
        let normalized = VFSPath.normalize(path)
        if normalized != path {
            fileBuffers[normalized] = content
        }
        bufferRevision &+= 1
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
                // Half-open sockets often leave RPCs hanging — force a clean reconnect.
                self.log.error("VFS RPC timed out id=\(id) method=\(method, privacy: .public)")
                if self.wantsRunning {
                    self.scheduleReconnect(reason: "request timeout")
                }
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

        // Probe: initialize once the socket is up. Only mark `.connected` after initialize
        // so clients never apply a stale tree/branch while `isReady` is true.
        Task { @MainActor [weak self] in
            guard let self, self.wantsRunning else { return }
            // Small delay so the handshake can complete.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard self.webSocket === task else { return }
            do {
                _ = try await self.initialize()
                self.connectionState = .connected
                self.reconnectAttempt = 0
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

        // Responses must be applied immediately so waiting `call()` continuations resume.
        if let id = inbound.id?.intValue {
            if let cont = pending.removeValue(forKey: id) {
                cont.resume(returning: data)
            }
            return
        }

        // Notifications (no id). Never await RPC work on the receive path —
        // `applyDidChange` issues `vfs/read` / `initialize` which need this loop
        // to still call `receive()`. Awaiting here deadlocks until the 30s timeout.
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
            // Always re-read when notified (host/container edits should reach the open buffer).
            do {
                _ = try await readStreaming(path: change.path)
            } catch {
                log.error("selective reload failed: \(error.localizedDescription, privacy: .public)")
            }
        case .create, .remove, .rename:
            // Atomic saves often emit remove+create. Refresh open buffer by path first
            // so the editor can hot-reload; then re-walk the tree without dropping focus.
            let path = change.path
            if change.type == .remove {
                // If the path still exists (rename race), re-read; else drop cache.
                do {
                    _ = try await readStreaming(path: path)
                } catch {
                    fileBuffers.removeValue(forKey: path)
                    bufferRevision &+= 1
                }
            } else {
                _ = try? await readStreaming(path: path)
            }
            do {
                _ = try await initialize(root: nil)
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
        // Drop snapshot so reconnect cannot re-apply an old tree with a wrong branch.
        clearWorkspaceSnapshot()
    }

    private func failPending(with error: Error) {
        let pending = self.pending
        self.pending.removeAll()
        for (_, cont) in pending {
            cont.resume(throwing: error)
        }
    }
}
