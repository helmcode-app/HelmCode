//
//  CodeMirrorHostView.swift
//  HelmCode
//
//  SwiftUI host for the offline CodeMirror 6 bundle (document, bookmarks, commands).
//

import SwiftUI
import WebKit

struct CodeMirrorHostView: UIViewRepresentable {
    var text: String
    var language: CodeMirrorLanguage
    var isDark: Bool
    var isEditable: Bool = true
    /// 1-based bookmarked lines for the open file.
    var bookmarkLines: [Int] = []
    /// When non-nil, scroll/select this line after the next document push.
    var revealLine: Int? = nil
    /// Changes when a new reveal is requested (even for the same line).
    var revealGeneration: Int = 0
    var onToggleBookmark: ((Int, String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> CodeMirrorWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(context.coordinator, name: CodeMirrorBundle.messageHandlerName)

        let webView = CodeMirrorWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.bind(webView)
        context.coordinator.loadEditor()
        return webView
    }

    func updateUIView(_ webView: CodeMirrorWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.bind(webView)
        context.coordinator.syncToWebView()
    }

    static func dismantleUIView(_ uiView: CodeMirrorWebView, coordinator: Coordinator) {
        uiView.onCustomCommand = nil
        uiView.configuration.userContentController
            .removeScriptMessageHandler(forName: CodeMirrorBundle.messageHandlerName)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: CodeMirrorHostView
        weak var webView: CodeMirrorWebView?

        private var isReady = false
        private var lastPayloadKey: String?
        private var lastBookmarkKey: String?
        private var lastRevealedLineToken: String?

        init(parent: CodeMirrorHostView) {
            self.parent = parent
        }

        func bind(_ webView: CodeMirrorWebView) {
            self.webView = webView
            webView.onCustomCommand = { [weak self] command in
                self?.run(command)
            }
        }

        func loadEditor() {
            guard let webView else { return }
            guard let url = CodeMirrorBundle.indexHTMLURL() else {
                assertionFailure("CodeMirror index.html missing from app bundle")
                return
            }
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }

        func syncToWebView() {
            pushDocumentIfNeeded()
            pushBookmarksIfNeeded()
            revealLineIfNeeded()
            requestRelayout()
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
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                markReady()
            case "toggleBookmark":
                let line = body["line"] as? Int
                    ?? (body["line"] as? Double).map { Int($0) }
                    ?? 0
                let lineText = body["lineText"] as? String ?? ""
                guard line >= 1 else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onToggleBookmark?(line, lineText)
                }
            default:
                break
            }
        }

        func run(_ command: CodeMirrorCommand) {
            // Hardware ⌘F lands here via UIKeyCommand (system often swallows it before JS).
            evaluate(CodeMirrorBundle.runCommandJavaScript(command))
        }

        private func markReady() {
            isReady = true
            lastPayloadKey = nil
            lastBookmarkKey = nil
            lastRevealedLineToken = nil
            syncToWebView()
        }

        private func pushDocumentIfNeeded() {
            guard isReady else { return }

            let key = documentKey
            guard key != lastPayloadKey else { return }
            lastPayloadKey = key
            // Document rebuild clears gutter; re-push bookmarks next.
            lastBookmarkKey = nil

            let payload: [String: Any] = [
                "text": parent.text,
                "language": parent.language.rawValue,
                "dark": parent.isDark,
                "readOnly": !parent.isEditable,
                "bookmarks": parent.bookmarkLines,
            ]
            guard let json = Self.jsonString(payload) else { return }

            evaluate(CodeMirrorBundle.setDocumentJavaScript(jsonObjectLiteral: json)) { [weak self] in
                self?.lastBookmarkKey = self?.bookmarkKey
                self?.revealLineIfNeeded()
            }
        }

        private func pushBookmarksIfNeeded() {
            guard isReady else { return }
            let key = bookmarkKey
            guard key != lastBookmarkKey else { return }
            lastBookmarkKey = key
            guard let json = Self.jsonString(parent.bookmarkLines) else { return }
            evaluate(CodeMirrorBundle.setBookmarksJavaScript(linesJSONArray: json))
        }

        private func revealLineIfNeeded() {
            guard isReady, let line = parent.revealLine, line >= 1 else { return }
            let token = "\(documentKey)|\(line)|\(parent.revealGeneration)"
            guard token != lastRevealedLineToken else { return }
            lastRevealedLineToken = token

            // After setDocument, wait a frame so layout/line map is ready.
            DispatchQueue.main.async { [weak self] in
                self?.evaluate(CodeMirrorBundle.goToLineJavaScript(line))
            }
        }

        private func requestRelayout() {
            guard isReady else { return }
            evaluate(CodeMirrorBundle.relayoutJavaScript)
        }

        private func evaluate(_ script: String, completion: (() -> Void)? = nil) {
            guard let webView else {
                completion?()
                return
            }
            webView.evaluateJavaScript(script) { _, _ in
                completion?()
            }
        }

        private var documentKey: String {
            [
                parent.language.rawValue,
                parent.isDark ? "d" : "l",
                parent.isEditable ? "e" : "r",
                parent.text,
            ].joined(separator: "\u{1e}")
        }

        private var bookmarkKey: String {
            parent.bookmarkLines.map(String.init).joined(separator: ",")
        }

        private static func jsonString(_ value: Any) -> String? {
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }
    }
}
