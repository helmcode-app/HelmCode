//
//  TerminalHostView.swift
//  HelmCode
//
//  SwiftUI host for the offline xterm.js WebSSH client (runner-core /v1/terminal).
//  Background tracks UIColor.systemBackground (same as the center code column).
//

import SwiftUI
import WebKit

struct TerminalHostView: UIViewRepresentable {
    var baseURLString: String
    var apiToken: String
    /// Matches `@Environment(\.colorScheme)` so forced light/dark app themes work.
    var isDark: Bool
    /// Bump to force reconnect with current credentials.
    var reconnectGeneration: UInt64 = 0
    var isActive: Bool = true
    var onStatus: ((String, TerminalLinkStatus) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> TerminalWebContainer {
        let container = TerminalWebContainer()
        container.onBoundsChange = { [weak coordinator = context.coordinator] in
            coordinator?.scheduleFit()
        }

        let webView = Self.makeWebView(coordinator: context.coordinator)
        container.embed(webView)
        container.applySystemBackground()
        context.coordinator.bind(webView)
        context.coordinator.loadTerminal()
        return container
    }

    func updateUIView(_ container: TerminalWebContainer, context: Context) {
        context.coordinator.parent = self
        container.applySystemBackground()
        if let webView = container.webView {
            context.coordinator.bind(webView)
            webView.backgroundColor = .systemBackground
            webView.scrollView.backgroundColor = .systemBackground
        }
        context.coordinator.syncColorScheme()
        context.coordinator.syncConnection()
        context.coordinator.scheduleFit()
    }

    static func dismantleUIView(_ uiView: TerminalWebContainer, coordinator: Coordinator) {
        coordinator.teardown()
        uiView.webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: TerminalBundle.messageHandlerName)
    }

    // MARK: - WebView factory

    private static func makeWebView(coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(coordinator, name: TerminalBundle.messageHandlerName)
        // Allow local file loads for sibling terminal.bundle.js
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        // Opaque + systemBackground: keyboard resize must not flash a foreign color.
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        if #available(iOS 15.0, *) {
            webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        webView.clipsToBounds = true
        webView.navigationDelegate = coordinator
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif
        return webView
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: TerminalHostView
        weak var webView: WKWebView?

        private var isPageReady = false
        private var lastConnectKey: String?
        private var lastReconnectGeneration: UInt64 = 0
        private var lastSchemeIsDark: Bool?
        private var pendingConnect = false
        private var fitWorkItem: DispatchWorkItem?

        init(parent: TerminalHostView) {
            self.parent = parent
        }

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

        func syncColorScheme() {
            guard isPageReady else { return }
            let isDark = parent.isDark
            if lastSchemeIsDark == isDark { return }
            lastSchemeIsDark = isDark
            evaluate(TerminalBundle.setColorSchemeJavaScript(isDark: isDark))
        }

        func syncConnection() {
            guard isPageReady else {
                pendingConnect = parent.isActive
                return
            }
            // Theme first so the first paint matches the editor column.
            syncColorScheme()

            guard parent.isActive else {
                if lastConnectKey != nil {
                    evaluate(TerminalBundle.disconnectJavaScript)
                    lastConnectKey = nil
                }
                return
            }

            let key = "\(parent.baseURLString)|\(parent.apiToken)"
            let needsConnect =
                lastConnectKey != key
                || parent.reconnectGeneration != lastReconnectGeneration
                || lastConnectKey == nil

            guard needsConnect else {
                scheduleFit()
                return
            }

            lastConnectKey = key
            lastReconnectGeneration = parent.reconnectGeneration
            evaluate(
                TerminalBundle.connectJavaScript(
                    baseURL: parent.baseURLString,
                    token: parent.apiToken
                )
            )
        }

        func scheduleFit() {
            guard isPageReady, parent.isActive else { return }
            fitWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.evaluate(TerminalBundle.fitJavaScript)
            }
            fitWorkItem = work
            // Slight delay lets Auto Layout + WebKit commit the new frame first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        func teardown() {
            fitWorkItem?.cancel()
            evaluate(TerminalBundle.disconnectJavaScript)
            isPageReady = false
            lastConnectKey = nil
            lastSchemeIsDark = nil
        }

        // MARK: WKNavigationDelegate

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // JS also posts ready; keep a fallback if bridge message is late.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, !self.isPageReady else { return }
                self.markPageReady()
            }
        }

        // MARK: WKScriptMessageHandler

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == TerminalBundle.messageHandlerName else { return }
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                markPageReady()
            case "status":
                let text = body["text"] as? String ?? ""
                let kind = TerminalLinkStatus(kind: body["kind"] as? String ?? "info")
                parent.onStatus?(text, kind)
            default:
                break
            }
        }

        private func markPageReady() {
            isPageReady = true
            lastSchemeIsDark = nil
            syncColorScheme()
            if pendingConnect || parent.isActive {
                pendingConnect = false
                syncConnection()
            }
            scheduleFit()
        }

        private func evaluate(_ script: String) {
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
