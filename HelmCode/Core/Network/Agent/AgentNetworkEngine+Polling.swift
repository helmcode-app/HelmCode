//
//  AgentNetworkEngine+Polling.swift
//  HelmCode
//
//  History poll loop and multi-step turn completion heuristics.
//

import Foundation
import os.log

extension AgentNetworkEngine {

    // MARK: - History polling

    func startPolling(sessionId: String) {
        stopPolling()
        turnStablePolls = 0
        turnLastFingerprint = nil
        let started = Date()
        // Agent turns with tools can run long; ask still benefits from a high ceiling.
        let maxWait: TimeInterval = 30 * 60
        // OpenCode multi-step turns emit several assistant messages (think → tool → answer).
        // Require N consecutive polls with identical fingerprint + no pending work.
        let requiredStablePolls = 2
        let baseline = timelineIDsBeforeTurn
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollHistoryOnce(sessionId: sessionId)
                if case .succeeded = self.phase { break }
                if case .failed = self.phase { break }
                if case .cancelled = self.phase { break }

                if self.phase.isBusy {
                    let fingerprint = self.turnFingerprint(after: baseline)
                    if fingerprint == self.turnLastFingerprint {
                        self.turnStablePolls += 1
                    } else {
                        self.turnLastFingerprint = fingerprint
                        self.turnStablePolls = 0
                    }

                    // Complete only when every *new* agent-side message is done and
                    // history stopped changing (avoids success on the first of 4 steps).
                    if self.turnStablePolls >= requiredStablePolls,
                       !self.hasPendingAgentWork(after: baseline),
                       let summary = self.newestCompletedAnswerText(after: baseline) {
                        self.result = AgentResult.sessionSummary(
                            sessionId: sessionId,
                            status: .succeeded,
                            summary: summary
                        )
                        self.phase = .succeeded
                        self.pollStatus = .succeeded
                        self.stopPolling()
                        break
                    }
                }

                if Date().timeIntervalSince(started) > maxWait, self.phase.isBusy {
                    let message =
                        "No completed assistant reply within \(Int(maxWait / 60))m. Check OPENCODE_API_KEY, model, and opencode serve logs."
                    self.phase = .failed(message)
                    self.lastError = message
                    self.pollStatus = .failed
                    self.stopPolling()
                    break
                }
                try? await Task.sleep(nanoseconds: UInt64(self.pollInterval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollHistoryOnce(sessionId: String) async {
        do {
            let history = try await api.sessionHistory(id: sessionId, limit: 200)
            applyHistory(history)
        } catch {
            log.debug("session history poll soft-fail: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Turn completion

    /// Fingerprint of new timeline rows so multi-step turns settle before success.
    func turnFingerprint(after baseline: Set<String>) -> String {
        eventLog
            .compactMap { entry -> String? in
                guard let tid = entry.detail?["timelineId"]?.stringValue,
                      !tid.isEmpty,
                      !baseline.contains(tid) else { return nil }
                let done = entry.detail?["done"]?.boolValue ?? false
                let kind = entry.detail?["kind"]?.stringValue ?? ""
                // Include message length so streaming text updates reset stability.
                return "\(tid):\(done):\(kind):\(entry.message.count)"
            }
            .joined(separator: "|")
    }

    /// True while any new agent-side row is still in-flight (`done != true`).
    func hasPendingAgentWork(after baseline: Set<String>) -> Bool {
        for entry in eventLog {
            guard let tid = entry.detail?["timelineId"]?.stringValue,
                  !tid.isEmpty,
                  !baseline.contains(tid) else { continue }
            if entry.stage == .userCommand { continue }
            let done = entry.detail?["done"]?.boolValue ?? false
            if !done { return true }
        }
        // Also: no agent-side rows yet after the user prompt → still waiting.
        let hasAgentRow = eventLog.contains { entry in
            guard let tid = entry.detail?["timelineId"]?.stringValue,
                  !tid.isEmpty,
                  !baseline.contains(tid) else { return false }
            return entry.stage != .userCommand
        }
        return !hasAgentRow
    }

    /// Prefer final answer text (not pure reasoning / tool placeholders).
    func newestCompletedAnswerText(after baseline: Set<String>) -> String? {
        for entry in eventLog.reversed() {
            guard entry.stage == .llmInvoke else { continue }
            guard let timelineId = entry.detail?["timelineId"]?.stringValue,
                  !timelineId.isEmpty,
                  !baseline.contains(timelineId) else { continue }
            let done = entry.detail?["done"]?.boolValue ?? false
            guard done else { continue }

            let kind = (entry.detail?["kind"]?.stringValue ?? "").lowercased()
            if kind == "reasoning" || kind == "tool" { continue }

            if let answer = entry.detail?["answer"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !answer.isEmpty,
               answer != "Working…" {
                return answer
            }

            let text = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "Working…" else { continue }
            // Skip tool-only placeholders like "[tool:bash]".
            if text.hasPrefix("[tool:") { continue }
            return text
        }
        // Fallback: any completed assistant text (including tool labels) if no pure answer.
        for entry in eventLog.reversed() {
            guard entry.stage == .llmInvoke || entry.stage == .testing else { continue }
            guard let timelineId = entry.detail?["timelineId"]?.stringValue,
                  !timelineId.isEmpty,
                  !baseline.contains(timelineId) else { continue }
            let done = entry.detail?["done"]?.boolValue ?? false
            guard done else { continue }
            let text = entry.message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "Working…" else { continue }
            return text
        }
        return nil
    }
}
