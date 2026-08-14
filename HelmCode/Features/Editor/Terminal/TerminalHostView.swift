//
//  TerminalHostView.swift
//  HelmCode
//
//  SwiftUI host for the offline xterm.js WebSSH client (runner-core /v1/terminal).
//  Connection / bridge logic: TerminalHostCoordinator.
//

import SwiftUI
import WebKit

struct TerminalHostView: UIViewRepresentable {
    var baseURLString: String
    var apiToken: String
    var workspaceId: String = HelmWorkspace.defaultID
    var projectID: String
    var isDark: Bool
    var reconnectGeneration: UInt64 = 0
    var sessionEpoch: UInt64 = 0
    /// Panel on-screen (focus/fit). Hiding does not kill a live PTY.
    var isVisible: Bool = true
    var onStatus: ((String, TerminalLinkStatus) -> Void)?
    var onSessionEnded: ((String) -> Void)?

    func makeCoordinator() -> TerminalHostCoordinator {
        TerminalHostCoordinator(parent: self)
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
        context.coordinator.applyUpdateCycle()
    }

    static func dismantleUIView(_ uiView: TerminalWebContainer, coordinator: TerminalHostCoordinator) {
        coordinator.teardown()
        uiView.webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: TerminalBundle.messageHandlerName)
    }

    // MARK: - WebView factory

    private static func makeWebView(coordinator: TerminalHostCoordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(coordinator, name: TerminalBundle.messageHandlerName)
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
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
}
