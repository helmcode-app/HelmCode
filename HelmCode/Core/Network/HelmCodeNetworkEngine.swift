//
//  HelmCodeNetworkEngine.swift
//  HelmCode
//
//  Observable task/session state machine on top of RunnerCoreAPIClient.
//

import Combine
import Foundation

/// UI-facing network engine: health, async submit, timer poll, cancel.
@MainActor
final class HelmCodeNetworkEngine: ObservableObject {

    // MARK: Published surface

    @Published private(set) var connectionState: BackendConnectionState = .unknown
    @Published private(set) var health: HealthCheck?
    @Published private(set) var runtimeStatus: RuntimeStatus?
    @Published private(set) var helmMode: HelmMode = .openCore
    @Published private(set) var promptCharacterLimit: Int = HelmMode.openCore.promptCharacterLimit
    @Published private(set) var concurrentTaskLimit: Int = HelmMode.openCore.concurrentTaskLimit

    @Published private(set) var phase: EngineTaskPhase = .idle
    @Published private(set) var activeTaskID: String?
    @Published private(set) var pollStatus: TaskStatus?
    @Published private(set) var events: [TaskProgressEvent] = []
    @Published private(set) var result: AgentResult?
    @Published private(set) var lastError: String?

    @Published var baseURLString: String {
        didSet { api.baseURLString = baseURLString }
    }

    @Published var apiToken: String {
        didSet { api.apiToken = apiToken }
    }

    // MARK: Internals

    private var api: RunnerCoreAPIClient
    private var pollTimer: Timer?
    private var pollInFlight = false
    private let pollInterval: TimeInterval

    init(
        // Docker compose maps host 18080 → container 8080 (see runner-core compose.dev.yaml).
        baseURL: String = "http://127.0.0.1:18080",
        apiToken: String = "",
        pollInterval: TimeInterval = 0.75,
        session: URLSession = .shared
    ) {
        self.baseURLString = baseURL
        self.apiToken = apiToken
        self.pollInterval = pollInterval
        self.api = RunnerCoreAPIClient(
            baseURLString: baseURL,
            apiToken: apiToken,
            session: session
        )
    }

    // MARK: - Public API

    func checkBackendHealth() async {
        connectionState = .checking
        lastError = nil

        do {
            let healthBody = try await api.health()
            health = healthBody
            applyMode(healthBody.mode)
            connectionState = .online

            if let statusBody = try? await api.status() {
                runtimeStatus = statusBody
                applyMode(statusBody.mode)
            }
        } catch {
            health = nil
            runtimeStatus = nil
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            connectionState = .offline(message)
            lastError = message
        }
    }

    @discardableResult
    func submitAsyncTask(prompt: String) async throws -> TaskAcceptedResponse {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HelmNetworkError.emptyPrompt }
        guard trimmed.count <= promptCharacterLimit else {
            throw HelmNetworkError.promptTooLong(limit: promptCharacterLimit)
        }
        guard !phase.isBusy else { throw HelmNetworkError.alreadyRunning }

        if let active = runtimeStatus?.activeTaskCount, active >= concurrentTaskLimit {
            throw HelmNetworkError.concurrentLimit(limit: concurrentTaskLimit)
        }

        phase = .submitting
        lastError = nil
        result = nil
        events = []
        pollStatus = .queued
        activeTaskID = nil

        do {
            let accepted = try await api.submitTask(TaskRequest.commander(prompt: trimmed))
            activeTaskID = accepted.id
            pollStatus = accepted.status
            phase = .running
            startPolling(id: accepted.id)
            return accepted
        } catch {
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            lastError = phaseFailedMessage
            throw error
        }
    }

    func pollTaskStatus(id: String) async {
        guard !pollInFlight else { return }
        pollInFlight = true
        defer { pollInFlight = false }

        do {
            applyPoll(try await api.pollTask(id: id))
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func cancelActiveTask() async {
        guard let id = activeTaskID else { return }
        do {
            _ = try await api.cancelTask(id: id)
            phase = .cancelled
            pollStatus = .cancelled
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func resetSession() {
        stopPolling()
        phase = .idle
        activeTaskID = nil
        pollStatus = nil
        events = []
        result = nil
        lastError = nil
    }

    // MARK: - Polling

    private func startPolling(id: String) {
        stopPolling()
        Task { await pollTaskStatus(id: id) }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollTaskStatus(id: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func applyPoll(_ poll: TaskPollResponse) {
        activeTaskID = poll.id
        pollStatus = poll.status

        if poll.events.count >= events.count {
            events = poll.events
        } else if !poll.events.isEmpty {
            events = poll.events
        }

        if let terminal = poll.result {
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
            Task { await refreshRuntimeStatusQuietly() }
            return
        }

        if poll.status.isTerminal {
            stopPolling()
            switch poll.status {
            case .succeeded: phase = .succeeded
            case .cancelled: phase = .cancelled
            case .failed: phase = .failed(lastError ?? "Task failed")
            default: break
            }
        } else {
            phase = .running
        }
    }

    private func applyMode(_ mode: HelmMode) {
        helmMode = mode
        promptCharacterLimit = mode.promptCharacterLimit
        concurrentTaskLimit = mode.concurrentTaskLimit
    }

    private var phaseFailedMessage: String? {
        if case .failed(let msg) = phase { return msg }
        return nil
    }

    private func refreshRuntimeStatusQuietly() async {
        if let statusBody = try? await api.status() {
            runtimeStatus = statusBody
            applyMode(statusBody.mode)
        }
    }
}
