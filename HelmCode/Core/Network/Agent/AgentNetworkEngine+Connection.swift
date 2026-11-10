//
//  AgentNetworkEngine+Connection.swift
//  HelmCode
//
//  Sessions health probe, reconnect backoff, and model catalog refresh.
//  See AgentNetworkEngine.swift for the full file map.
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
                    self.startEvents()
                    await self.refreshWorkspaces()
                    // Always probe the selected model so Cursor effort/fast/context
                    // are not replaced by another model's empty/default caps.
                    let probe = self.modelID.isEmpty ? nil : self.modelID
                    await self.refreshModelCatalog(force: true, probeModel: probe)
                    await self.refreshSessionList()
                    // Restore a non-empty session so the timeline is not blank.
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
        stopEvents()
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

    /// True when the live catalog has not been loaded from the runner yet.
    var needsModelCatalogRefresh: Bool {
        !modelCatalogLoaded || modelCatalog.isEmpty
    }

    /// Publish a catalog fetched outside the agent (e.g. Project Settings Models page).
    func adoptModelCatalog(
        _ mapped: [AgentModelOption],
        serverDefault: String? = nil,
        thinkLevels: [String]? = nil,
        thinkingLevels: [String]? = nil,
        contextLevels: [String]? = nil,
        context: String? = nil,
        supportsFast: Bool? = nil
    ) {
        applyHarnessCatalog(
            models: mapped,
            serverDefault: serverDefault,
            thinkLevels: thinkLevels,
            thinkingLevels: thinkingLevels,
            contextLevels: contextLevels,
            context: context,
            supportsFast: supportsFast
        )
    }

    /// Pull models + think/fast/context capabilities for the connected harness.
    /// Pass `probeModel` after a picker selection so Cursor-style agents advertise
    /// per-model effort/fast/context lists.
    func refreshModelCatalog(force: Bool = false, probeModel: String? = nil) async {
        let effectiveProbe = {
            let raw = (probeModel ?? modelID).trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.isEmpty ? nil : raw
        }()
        if modelCatalogLoaded, !force, probeModel == nil { return }
        // Soft open of an already-probed model: reuse cached knobs, skip network thrash.
        if modelCatalogLoaded,
           !force,
           let effectiveProbe,
           modelCapsByID[effectiveProbe] != nil {
            if effectiveProbe == modelID {
                applyCachedCapsForCurrentModel()
            }
            return
        }
        modelCatalogGeneration += 1
        let generation = modelCatalogGeneration
        do {
            let response = try await api.sessionModels(
                forceRefresh: force,
                probeModel: effectiveProbe
            )
            guard generation == modelCatalogGeneration else { return }
            let mapped = AgentModelOption.fromResponse(response)
            let caps = AgentModelCaps(
                thinkLevels: AgentThinkLevel.fromWire(response.thinkLevels ?? []),
                thinkingLevels: AgentThinkLevel.fromWire(response.thinkingLevels ?? []),
                contextLevels: AgentThinkLevel.fromWire(response.contextLevels ?? []),
                context: response.context,
                supportsFast: response.supportsFast ?? false
            )
            if let effectiveProbe {
                modelCapsByID[effectiveProbe] = caps
            }
            // Only publish knobs for the model the UI currently has selected.
            let publishCaps = effectiveProbe == nil || effectiveProbe == modelID
            applyHarnessCatalog(
                models: mapped,
                serverDefault: response.defaultModel,
                thinkLevels: publishCaps ? caps.thinkLevels.map(\.rawValue) : nil,
                thinkingLevels: publishCaps ? caps.thinkingLevels.map(\.rawValue) : nil,
                contextLevels: publishCaps ? caps.contextLevels.map(\.rawValue) : nil,
                context: publishCaps ? caps.context : nil,
                supportsFast: publishCaps ? caps.supportsFast : nil
            )
            log.info(
                "loaded \(mapped.count, privacy: .public) session models; probe=\(effectiveProbe ?? "-", privacy: .public) think=\(caps.thinkLevels.count, privacy: .public) thinking=\(caps.thinkingLevels.count, privacy: .public) context=\(caps.contextLevels.count, privacy: .public) fast=\(caps.supportsFast, privacy: .public) default=\(response.defaultModel ?? "-", privacy: .public)"
            )
        } catch {
            log.debug("session models soft-fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Instantly apply cached Cursor caps for `modelID` (avoids Effort/Fast flicker).
    func applyCachedCapsForCurrentModel() {
        guard let caps = modelCapsByID[modelID] else { return }
        applyHarnessCatalog(
            models: modelCatalog,
            serverDefault: nil,
            thinkLevels: caps.thinkLevels.map(\.rawValue),
            thinkingLevels: caps.thinkingLevels.map(\.rawValue),
            contextLevels: caps.contextLevels.map(\.rawValue),
            context: caps.context,
            supportsFast: caps.supportsFast
        )
    }

    private func applyHarnessCatalog(
        models mapped: [AgentModelOption],
        serverDefault: String?,
        thinkLevels: [String]?,
        thinkingLevels: [String]?,
        contextLevels: [String]?,
        context: String?,
        supportsFast: Bool?
    ) {
        let newIDs = mapped.map(\.id)
        let oldIDs = modelCatalog.map(\.id)
        if newIDs != oldIDs {
            modelCatalog = mapped
        }
        modelCatalogLoaded = true

        if mapped.isEmpty {
            modelID = ""
        } else if !mapped.contains(where: { $0.id == modelID }) {
            modelID = AgentModelOption.preferredDefaultID(
                in: mapped,
                serverDefault: serverDefault
            ) ?? mapped[0].id
        }

        // nil = leave unchanged (e.g. Settings refreshed models only).
        if let thinkLevels {
            let levels = AgentThinkLevel.fromWire(thinkLevels)
            availableThinkLevels = levels
            if !levels.isEmpty, !levels.contains(where: { $0.rawValue == thinkLevel.rawValue }) {
                thinkLevel = levels.first(where: { $0.rawValue == "medium" }) ?? levels[0]
            }
        }

        if let thinkingLevels {
            let levels = AgentThinkLevel.fromWire(thinkingLevels)
            availableThinkingLevels = levels
            if levels.isEmpty {
                thinkingEnabled = true
            }
        }

        if let contextLevels {
            let levels = AgentThinkLevel.fromWire(contextLevels)
            availableContextLevels = levels
            if levels.isEmpty {
                contextLevel = AgentThinkLevel(rawValue: "")
            } else if let context,
                      levels.contains(where: { $0.rawValue == context }) {
                contextLevel = AgentThinkLevel(rawValue: context)
            } else if !levels.contains(where: { $0.rawValue == contextLevel.rawValue }) {
                contextLevel = levels[0]
            }
            syncUsageMeterToContextLevel()
        } else if let context, !context.isEmpty {
            contextLevel = AgentThinkLevel(rawValue: context)
            syncUsageMeterToContextLevel()
        }

        if let supportsFast {
            supportsFastMode = supportsFast
            if !supportsFast {
                fastMode = false
            }
        }
    }

    /// Keep the composer context chip size aligned with the selected context level.
    func syncUsageMeterToContextLevel() {
        guard let tokens = SessionUsage.tokens(fromContextLabel: contextLevel.rawValue),
              tokens > 0 else { return }
        if var usage = sessionUsage {
            if usage.size == tokens { return }
            usage.size = tokens
            usage.used = min(usage.used, tokens)
            sessionUsage = usage
        } else {
            sessionUsage = SessionUsage(used: 0, size: tokens)
        }
    }

    // MARK: - SSE events

    func startEvents() {
        stopEvents()
        eventsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.wantsRunning, !Task.isCancelled {
                do {
                    for try await event in self.api.sessionEvents() {
                        if Task.isCancelled || !self.wantsRunning { return }
                        self.handleSessionStreamEvent(event)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    self.log.debug(
                        "session events soft-fail: \(error.localizedDescription, privacy: .public)"
                    )
                }
                guard self.wantsRunning, !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    func stopEvents() {
        eventsTask?.cancel()
        eventsTask = nil
    }

    func handleSessionStreamEvent(_ event: SessionStreamEventDTO) {
        switch event.type {
        case "session.usage":
            // Ignore events for other chats when one is selected.
            if let sid = event.sessionId, let active = sessionID, sid != active {
                return
            }
            let fallbackSize = sessionUsage?.size
                ?? SessionUsage.tokens(fromContextLabel: contextLevel.rawValue)
            if let usage = SessionUsage.parse(
                from: event.data?.objectValue,
                fallbackSize: fallbackSize
            ) {
                applyUsageUpdate(usage)
            } else if case .object(let obj) = event.data,
                      let usage = SessionUsage.parse(object: obj, fallbackSize: fallbackSize) {
                applyUsageUpdate(usage)
            }
        default:
            break
        }
    }
}
