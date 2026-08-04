//
//  TerminalHostCoordinator.swift
//  HelmCode
//
//  WKWebView navigation + JS bridge + WebSSH connection state machine.
//  Owned by TerminalHostView (UIViewRepresentable).
//
//  Session policy:
//  • ⌘J hide/show with live PTY → keep socket + scrollback (deduped connect).
//  • sessionEpoch bump / project clear / remote exit → wipe + disconnect.
//  • Never call connect() on every updateUIView (thrashes into connecting/error).
//

import UIKit
import WebKit

@MainActor
final class TerminalHostCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var parent: TerminalHostView
    weak var webView: WKWebView?

    private var isPageReady = false
    /// True only after JS `status` kind `ok` (connected / ready).
    private var hasLiveSession = false
    /// Dedupes connect() across SwiftUI update passes.
    private var lastAttemptToken: String?
    private var lastConnectKey: String?
    private var lastReconnectGeneration: UInt64 = 0
    private var lastSessionEpoch: UInt64 = 0
    private var lastSchemeIsDark: Bool?
    private var lastIsVisible = false
    private var becameVisible = false
    private var pendingConnect = false
    private var fitWorkItem: DispatchWorkItem?
    private var focusWorkItem: DispatchWorkItem?

    init(parent: TerminalHostView) {
        self.parent = parent
    }

    // MARK: - Lifecycle hooks (from TerminalHostView)

    func bind(_ webView: WKWebView) {
        self.webView = webView
    }

    func loadTerminal() {
        guard let webView else { return }
        guard let url = TerminalBundle.indexHTMLURL() else {
            assertionFailure("Terminal terminal.html missing from app bundle")
            parent.onStatus?("missing terminal assets", .err)
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Call first in `updateUIView` so re-show can clear a failed attempt token.
    func noteVisibilityEdge() {
        let visible = parent.isVisible
        becameVisible = visible && !lastIsVisible
        if becameVisible, !hasLiveSession {
            lastAttemptToken = nil
        }
        lastIsVisible = visible
    }

    func applyUpdateCycle() {
        noteVisibilityEdge()
        syncColorScheme()
        syncSessionEpoch()
        syncConnection()
        scheduleFit()
        scheduleFocusIfBecameVisible()
    }

    func teardown() {
        fitWorkItem?.cancel()
        focusWorkItem?.cancel()
        evaluate(TerminalBundle.resetSessionJavaScript)
        isPageReady = false
        markSessionDead()
        lastAttemptToken = nil
        lastSchemeIsDark = nil
        lastIsVisible = false
        becameVisible = false
    }

    // MARK: - Sync

    func syncColorScheme() {
        guard isPageReady else { return }
        let isDark = parent.isDark
        if lastSchemeIsDark == isDark { return }
        lastSchemeIsDark = isDark
        evaluate(TerminalBundle.setColorSchemeJavaScript(isDark: isDark))
    }

    func syncSessionEpoch() {
        guard isPageReady else { return }
        if parent.sessionEpoch != lastSessionEpoch {
            lastSessionEpoch = parent.sessionEpoch
            markSessionDead()
            lastAttemptToken = nil
            evaluate(TerminalBundle.resetSessionJavaScript)
        }
    }

    func syncConnection() {
        guard isPageReady else {
            pendingConnect = parent.isVisible && !parent.projectID.isEmpty
            return
        }

        if parent.projectID.isEmpty {
            if lastConnectKey != nil || hasLiveSession {
                markSessionDead()
                lastAttemptToken = nil
                evaluate(TerminalBundle.resetSessionJavaScript)
            }
            return
        }

        let key = connectionKey
        let gen = parent.reconnectGeneration
        let attemptToken = "\(key)|g\(gen)|e\(parent.sessionEpoch)"

        // Keep-alive: live PTY for this project — never reconnect on hide/show.
        if hasLiveSession, lastConnectKey == key, gen == lastReconnectGeneration {
            return
        }

        // Manual ↻ forces a new attempt.
        if gen != lastReconnectGeneration {
            lastReconnectGeneration = gen
            lastAttemptToken = nil
            markSessionDead()
        }

        // Not on-screen: do not open a shell in the background.
        guard parent.isVisible else { return }

        // Already kicked off connect for this project/gen/epoch — wait for ok/err.
        if lastAttemptToken == attemptToken {
            return
        }

        lastAttemptToken = attemptToken
        lastConnectKey = key
        lastReconnectGeneration = gen
        hasLiveSession = false
        evaluate(
            TerminalBundle.connectJavaScript(
                baseURL: parent.baseURLString,
                token: parent.apiToken
            )
        )
        scheduleFocus(delays: [0.08, 0.25, 0.5])
    }

    func scheduleFit() {
        guard isPageReady, parent.isVisible else { return }
        fitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.evaluate(TerminalBundle.fitJavaScript)
        }
        fitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    func scheduleFocusIfBecameVisible() {
        guard isPageReady, parent.isVisible, becameVisible else { return }
        scheduleFocus(delays: [0.05, 0.22])
        becameVisible = false
    }

    // MARK: - Private helpers

    private var connectionKey: String {
        "\(parent.projectID)|\(parent.baseURLString)|\(parent.apiToken)"
    }

    private func markSessionDead() {
        hasLiveSession = false
        lastConnectKey = nil
    }

    private func scheduleFocus(delays: [TimeInterval]) {
        guard isPageReady, parent.isVisible else { return }
        focusWorkItem?.cancel()
        for (index, delay) in delays.enumerated() {
            let work = DispatchWorkItem { [weak self] in
                self?.claimKeyboardFocus()
            }
            if index == delays.count - 1 {
                focusWorkItem = work
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func claimKeyboardFocus() {
        guard parent.isVisible, let webView else { return }
        if !webView.isFirstResponder {
            webView.becomeFirstResponder()
        }
        evaluate(TerminalBundle.focusJavaScript)
    }

    private func markPageReady() {
        isPageReady = true
        lastSchemeIsDark = nil
        lastSessionEpoch = parent.sessionEpoch
        syncColorScheme()
        if pendingConnect || parent.isVisible {
            pendingConnect = false
            lastAttemptToken = nil
            syncConnection()
        }
        if parent.isVisible {
            scheduleFit()
            scheduleFocus(delays: [0.1, 0.3])
        }
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isPageReady else { return }
            // Small delay: JS bridge `ready` may race with didFinish.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !self.isPageReady else { return }
                self.markPageReady()
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == TerminalBundle.messageHandlerName else { return }
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        DispatchQueue.main.async { [weak self] in
            self?.handleBridgeMessage(type: type, body: body)
        }
    }

    private func handleBridgeMessage(type: String, body: [String: Any]) {
        switch type {
        case "ready":
            markPageReady()

        case "status":
            let text = body["text"] as? String ?? ""
            let kind = TerminalLinkStatus(kind: body["kind"] as? String ?? "info")
            if kind == .ok {
                hasLiveSession = true
                lastConnectKey = connectionKey
            } else if kind == .err {
                hasLiveSession = false
            }
            parent.onStatus?(text, kind)
            if kind == .ok, parent.isVisible {
                scheduleFocus(delays: [0.05, 0.2])
            }

        case "sessionEnded":
            markSessionDead()
            lastAttemptToken = nil
            let reason = body["reason"] as? String ?? "exit"
            parent.onStatus?("exited", .info)
            parent.onSessionEnded?(reason)

        case "requestFocus":
            if parent.isVisible {
                scheduleFocus(delays: [0.0, 0.12])
            }

        default:
            break
        }
    }
}
