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
    /// When non-nil, mount `@codemirror/merge` unified merge (`text` = modified, this = original).
    var mergeOriginal: String? = nil
    /// 1-based bookmarked lines for the open file.
    var bookmarkLines: [Int] = []
    /// When non-nil, scroll/select this line after the next document push.
    var revealLine: Int? = nil
    /// Changes when a new reveal is requested (even for the same line).
    var revealGeneration: Int = 0
    /// When true, text-only updates use soft replace (hot reload) instead of setDocument.
    var preferSoftTextReplace: Bool = false
    /// When true, Swift drives progressive loads (skip auto setDocument from `text`).
    var streamMode: Bool = false
    /// Bump to clear CM and start a new stream (`setDocument("")`).
    var streamBeginGeneration: UInt64 = 0
    /// Bump with `streamChunkText` to append a chunk into CM.
    var streamChunkGeneration: UInt64 = 0
    var streamChunkText: String = ""
    /// Bump when stream completes so CM can re-sync bookmarks/layout against final `text`.
    var streamEndGeneration: UInt64 = 0
    var onToggleBookmark: ((Int, String) -> Void)?
    /// User edits from CodeMirror (do not push `setDocument` back for these).
    var onTextChange: ((String) -> Void)?
    /// Explicit save (⌘S / menu). Text is the latest document body.
    var onSave: ((String) -> Void)?

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
        private var lastMetaKey: String?
        private var lastBookmarkKey: String?
        private var lastRevealedLineToken: String?
        private var lastStreamBegin: UInt64 = 0
        private var lastStreamChunk: UInt64 = 0
        private var lastStreamEnd: UInt64 = 0
        /// Stream commands that arrived before the WKWebView JS bridge was ready.
        private var pendingStreamBegin = false
        private var pendingStreamChunks: [String] = []
        private var pendingStreamEndText: String?

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
            applyStreamCommandsIfNeeded()
            let didSoftReplace = pushDocumentIfNeeded()
            pushBookmarksIfNeeded()
            revealLineIfNeeded()
            // Relayout after full setDocument only — soft hot-reload avoids the flash.
            if !didSoftReplace {
                requestRelayout()
            }
        }

        private func applyStreamCommandsIfNeeded() {
            if parent.streamBeginGeneration != lastStreamBegin {
                lastStreamBegin = parent.streamBeginGeneration
                pendingStreamChunks.removeAll(keepingCapacity: true)
                pendingStreamEndText = nil
                if isReady {
                    beginStreamDocument()
                } else {
                    pendingStreamBegin = true
                }
            }
            if parent.streamChunkGeneration != lastStreamChunk {
                lastStreamChunk = parent.streamChunkGeneration
                let chunk = parent.streamChunkText
                if isReady {
                    // Ensure shell exists even if begin was skipped/raced.
                    if pendingStreamBegin {
                        beginStreamDocument()
                        pendingStreamBegin = false
                    }
                    appendStreamChunk(chunk)
                } else if !chunk.isEmpty {
                    pendingStreamChunks.append(chunk)
                }
            }
            if parent.streamEndGeneration != lastStreamEnd {
                lastStreamEnd = parent.streamEndGeneration
                let finalText = parent.text
                if isReady {
                    flushPendingStream()
                    endStreamDocument(finalText: finalText)
                } else {
                    pendingStreamEndText = finalText
                }
            }
        }

        private func flushPendingStream() {
            if pendingStreamBegin {
                beginStreamDocument()
                pendingStreamBegin = false
            }
            if !pendingStreamChunks.isEmpty {
                for chunk in pendingStreamChunks {
                    appendStreamChunk(chunk)
                }
                pendingStreamChunks.removeAll(keepingCapacity: false)
            }
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
            case "documentChange":
                let text = body["text"] as? String ?? ""
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Ignore CM echo while VFS is streaming chunks into the host buffer.
                    guard !self.parent.streamMode else { return }
                    // Mark payload as already matching so updateUIView won't re-setDocument.
                    self.lastPayloadKey = self.documentKey(forText: text)
                    self.parent.onTextChange?(text)
                }
            case "save":
                let text = body["text"] as? String ?? ""
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard !self.parent.streamMode else { return }
                    self.lastPayloadKey = self.documentKey(forText: text)
                    self.parent.onTextChange?(text)
                    self.parent.onSave?(text)
                }
            default:
                break
            }
        }

        func run(_ command: CodeMirrorCommand) {
            if command == .save {
                // Prefer JS path so we get the latest doc; it posts "save" back.
                evaluate(CodeMirrorBundle.runCommandJavaScript(command))
                return
            }
            // Hardware ⌘F lands here via UIKeyCommand (system often swallows it before JS).
            evaluate(CodeMirrorBundle.runCommandJavaScript(command))
        }

        private func markReady() {
            isReady = true
            lastPayloadKey = nil
            lastMetaKey = nil
            lastBookmarkKey = nil
            lastRevealedLineToken = nil
            // Drain stream queue before normal sync so final setDocument wins if already ended.
            flushPendingStream()
            if let end = pendingStreamEndText {
                pendingStreamEndText = nil
                endStreamDocument(finalText: end)
            }
            syncToWebView()
        }

        /// Begin a streamed document (empty shell); subsequent chunks use `appendStreamChunk`.
        func beginStreamDocument() {
            guard isReady else {
                pendingStreamBegin = true
                return
            }
            guard let json = documentPayloadJSON(text: "", bookmarks: []) else { return }
            lastPayloadKey = documentKey(forText: "")
            lastMetaKey = metaKey
            lastBookmarkKey = nil
            evaluate(CodeMirrorBundle.setDocumentJavaScript(jsonObjectLiteral: json))
        }

        /// Append one VFS chunk into the live CodeMirror document.
        func appendStreamChunk(_ text: String) {
            guard !text.isEmpty else { return }
            guard isReady else {
                pendingStreamChunks.append(text)
                return
            }
            guard let textJSON = Self.jsonEncode(text) else { return }
            evaluate(CodeMirrorBundle.appendDocumentTextJavaScript(jsonStringLiteral: textJSON))
        }

        /// Finalize stream with a full setDocument — authoritative content (append may have been partial).
        func endStreamDocument(finalText: String) {
            guard isReady else {
                pendingStreamEndText = finalText
                return
            }
            guard let json = documentPayloadJSON(text: finalText, bookmarks: parent.bookmarkLines) else { return }
            lastPayloadKey = documentKey(forText: finalText)
            lastMetaKey = metaKey
            lastBookmarkKey = nil
            pendingStreamBegin = false
            pendingStreamChunks.removeAll(keepingCapacity: false)
            pendingStreamEndText = nil
            evaluate(CodeMirrorBundle.setDocumentJavaScript(jsonObjectLiteral: json)) { [weak self] in
                self?.lastBookmarkKey = self?.bookmarkKey
                self?.revealLineIfNeeded()
                self?.requestRelayout()
            }
        }

        /// Returns `true` when a soft (hot-reload) replace was applied.
        @discardableResult
        private func pushDocumentIfNeeded() -> Bool {
            guard isReady else { return false }
            // During chunked load, host drives setDocument/append via stream APIs.
            if parent.streamMode { return false }

            let key = documentKey
            guard key != lastPayloadKey else { return false }

            let meta = metaKey
            let textOnlyChange = lastMetaKey == meta && lastPayloadKey != nil

            // Hot reload: same language/theme, body changed externally → soft replace.
            // Important: only commit lastPayloadKey after we have a valid JS payload.
            // Merge/diff surfaces always full-rebuild (unifiedMergeView binds original).
            if parent.mergeOriginal == nil, parent.preferSoftTextReplace, textOnlyChange {
                if let textJSON = Self.jsonEncode(parent.text) {
                    lastPayloadKey = key
                    // Don't re-push bookmarks on every remote keystroke-sized update —
                    // markers map through the change set.
                    evaluate(CodeMirrorBundle.replaceDocumentTextJavaScript(jsonStringLiteral: textJSON))
                    return true
                }
                // Fall through to full setDocument if encoding fails.
            }

            guard let json = documentPayloadJSON(
                text: parent.text,
                bookmarks: parent.mergeOriginal == nil ? parent.bookmarkLines : []
            ) else { return false }

            lastPayloadKey = key
            lastMetaKey = meta
            // Document rebuild clears gutter; re-push bookmarks next.
            lastBookmarkKey = nil

            evaluate(CodeMirrorBundle.setDocumentJavaScript(jsonObjectLiteral: json)) { [weak self] in
                self?.lastBookmarkKey = self?.bookmarkKey
                self?.revealLineIfNeeded()
            }
            return false
        }

        private func documentPayloadJSON(text: String, bookmarks: [Int]) -> String? {
            var payload: [String: Any] = [
                "text": text,
                "language": parent.language.rawValue,
                "dark": parent.isDark,
                "readOnly": !parent.isEditable || parent.mergeOriginal != nil,
                "bookmarks": bookmarks,
            ]
            if let original = parent.mergeOriginal {
                payload["merge"] = true
                payload["original"] = original
            }
            return Self.jsonEncode(payload)
        }

        private func pushBookmarksIfNeeded() {
            guard isReady else { return }
            guard parent.mergeOriginal == nil else { return }
            let key = bookmarkKey
            guard key != lastBookmarkKey else { return }
            lastBookmarkKey = key
            guard let json = Self.jsonEncode(parent.bookmarkLines) else { return }
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
            documentKey(forText: parent.text)
        }

        /// Language / theme / editability (excludes body text).
        private var metaKey: String {
            [
                parent.language.rawValue,
                parent.isDark ? "d" : "l",
                parent.isEditable ? "e" : "r",
                parent.mergeOriginal == nil ? "n" : "m",
            ].joined(separator: "\u{1e}")
        }

        private func documentKey(forText text: String) -> String {
            let original = parent.mergeOriginal ?? ""
            return metaKey + "\u{1e}" + text + "\u{1e}" + original
        }

        private var bookmarkKey: String {
            parent.bookmarkLines.map(String.init).joined(separator: ",")
        }

        /// Encode any JSON value including top-level String (JSONSerialization rejects bare strings).
        private static func jsonEncode(_ value: Any) -> String? {
            if let string = value as? String {
                guard let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]),
                      let json = String(data: data, encoding: .utf8) else { return nil }
                return json
            }
            if let int = value as? Int {
                return String(int)
            }
            guard JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }
    }
}

