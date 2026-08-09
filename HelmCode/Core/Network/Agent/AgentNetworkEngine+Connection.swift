//
//  AgentNetworkEngine+Connection.swift
//  HelmCode
//
//  Sessions health probe, reconnect backoff, and model catalog refresh.
//

import Foundation
import os.log

extension AgentNetworkEngine {

    // MARK: - Connect

    func connect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        healthTask?.cancel()

        socketState = reconnectAttempt == 0 ? .connecting : .reconnecting(attempt: reconnectAttempt)
        if !phase.isBusy {
            phase = .connecting
        }

        log.info("Agent sessions health check \(self.baseURLString, privacy: .public)")

        healthTask = Task { @MainActor [weak self] in
            guard let self, self.wantsRunning else { return }
            do {
                let health = try await self.api.sessionsHealth()
                guard self.wantsRunning else { return }
                if health.ok {
                    self.socketState = .connected
                    self.reconnectAttempt = 0
                    self.lastError = nil
                    if !self.phase.isBusy {
                        self.phase = .ready
                    }
                    self.log.info("Agent sessions ready")
                    await self.refreshModelCatalog()
                    await self.refreshSessionList()
                    // Restore a non-empty OpenCode session so the timeline is not blank.
                    await self.restoreSessionTimelineIfNeeded()
                } else {
                    let message = health.error ?? "sessions runtime not healthy"
                    throw AgentEngineError.closed(message)
                }
            } catch {
                let message = self.mapError(error)
                self.log.error("Agent sessions health failed: \(message, privacy: .public)")
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

    func reconnectNow(reason: String) {
        log.info("Agent reconnect: \(reason, privacy: .public)")
        scheduleReconnect(reason: reason)
    }

    func scheduleReconnect(reason: String) {
        guard wantsRunning else { return }
        reconnectTask?.cancel()
        healthTask?.cancel()
        reconnectAttempt += 1
        lastError = reason
        socketState = .reconnecting(attempt: reconnectAttempt)
        if !phase.isBusy {
            phase = .connecting
        }
        let delay = min(pow(1.6, Double(min(reconnectAttempt, 8))), 20.0)
        log.info("Agent reconnect in \(delay, privacy: .public)s — \(reason, privacy: .public)")
        reconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.wantsRunning, !Task.isCancelled else { return }
            self.connect()
        }
    }

    // MARK: - Model catalog

    /// Pull models available for currently authenticated OpenCode providers.
    /// Only publishes when the id set changes — prevents Menu/sheet scroll jumps.
    func refreshModelCatalog(force: Bool = false) async {
        if modelCatalogLoaded, !force { return }
        do {
            let response = try await api.sessionModels()
            let mapped = response.models.map(AgentModelOption.fromDTO)
            guard !mapped.isEmpty else { return }

            let newIDs = mapped.map(\.id)
            let oldIDs = modelCatalog.map(\.id)
            if newIDs != oldIDs {
                modelCatalog = mapped
                log.info(
                    "loaded \(mapped.count, privacy: .public) session models; default=\(response.default ?? "-", privacy: .public)"
                )
            }
            modelCatalogLoaded = true

            if !mapped.contains(where: { $0.id == modelID }) {
                modelID = response.default
                    ?? mapped.first(where: { $0.id.hasPrefix("opencode/") })?.id
                    ?? mapped[0].id
            }
        } catch {
            log.debug("session models soft-fail: \(error.localizedDescription, privacy: .public)")
            // Keep fallback catalog.
        }
    }
}
