//
//  CodeMirrorHostView.swift
//  HelmCode
//
//  WKWebView host for the bundled CodeMirror 6 editor.
//

import SwiftUI
import WebKit

struct CodeMirrorHostView: UIViewRepresentable {
    var text: String
    var language: CodeMirrorLanguage
    var isDark: Bool
    var isEditable: Bool = true
    var lineWrapping: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: CodeMirrorBundle.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.keyboardDismissMode = .interactive
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        context.coordinator.webView = webView
        context.coordinator.loadEditor(into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.pushDocumentIfNeeded()
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController
            .removeScriptMessageHandler(forName: CodeMirrorBundle.messageHandlerName)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CodeMirrorHostView
        weak var webView: WKWebView?

        private var isReady = false
        private var lastPayloadKey: String?

        init(parent: CodeMirrorHostView) {
            self.parent = parent
        }

        func loadEditor(into webView: WKWebView) {
            guard let url = CodeMirrorBundle.indexHTMLURL() else {
                assertionFailure("CodeMirror index.html missing from app bundle")
                return
            }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Fallback if the JS ready postMessage races load.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.isReady else { return }
                self.markReady()
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == CodeMirrorBundle.messageHandlerName else { return }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String,
               type == "ready" {
                markReady()
            }
        }

        private func markReady() {
            isReady = true
            lastPayloadKey = nil
            pushDocumentIfNeeded()
        }

        func pushDocumentIfNeeded() {
            guard isReady, let webView else { return }

            let key = documentKey
            guard key != lastPayloadKey else { return }
            lastPayloadKey = key

            let payload: [String: Any] = [
                "text": parent.text,
                "language": parent.language.rawValue,
                "dark": parent.isDark,
                "readOnly": !parent.isEditable,
                "wrap": parent.lineWrapping,
            ]

            guard
                let data = try? JSONSerialization.data(withJSONObject: payload),
                let json = String(data: data, encoding: .utf8)
            else { return }

            webView.evaluateJavaScript(
                "window.HelmCodeEditor && window.HelmCodeEditor.setDocument(\(json));",
                completionHandler: nil
            )
        }

        private var documentKey: String {
            [
                parent.language.rawValue,
                parent.isDark ? "d" : "l",
                parent.isEditable ? "e" : "r",
                parent.lineWrapping ? "w" : "n",
                parent.text,
            ].joined(separator: "\u{1e}")
        }
    }
}
