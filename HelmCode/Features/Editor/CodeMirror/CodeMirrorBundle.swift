//
//  CodeMirrorBundle.swift
//  HelmCode
//
//  Bundled CM6 asset lookup + JS bridge identifiers.
//

import Foundation

enum CodeMirrorBundle {
    /// `WKScriptMessageHandler` name (must match editor-entry.mjs postMessage).
    static let messageHandlerName = "helmEditor"

    /// Global installed by `editor.bundle.js`.
    static let jsGlobal = "window.HelmCodeEditor"

    // MARK: - Asset resolution

    /// Locates `index.html`. Xcode may flatten resources into the app root.
    static func indexHTMLURL(in bundle: Bundle = .main) -> URL? {
        let candidates: [URL?] = [
            bundle.url(forResource: "index", withExtension: "html"),
            bundle.url(forResource: "index", withExtension: "html", subdirectory: "CodeMirror"),
            bundle.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: "Features/Editor/CodeMirror"
            ),
        ]
        return candidates.compactMap { $0 }.first
    }

    // MARK: - JS bridge snippets

    static func setDocumentJavaScript(jsonObjectLiteral: String) -> String {
        "\(jsGlobal) && \(jsGlobal).setDocument(\(jsonObjectLiteral));"
    }

    /// Soft-replace document body; preserves first visible line at top of viewport.
    static func replaceDocumentTextJavaScript(jsonStringLiteral: String) -> String {
        "\(jsGlobal) && \(jsGlobal).replaceDocumentText && \(jsGlobal).replaceDocumentText(\(jsonStringLiteral), { preserveTopLine: true });"
    }

    /// Append a chunk at end of doc (chunked VFS streaming).
    static func appendDocumentTextJavaScript(jsonStringLiteral: String) -> String {
        "\(jsGlobal) && \(jsGlobal).appendDocumentText && \(jsGlobal).appendDocumentText(\(jsonStringLiteral));"
    }

    static var relayoutJavaScript: String {
        "\(jsGlobal) && \(jsGlobal).relayout && \(jsGlobal).relayout();"
    }

    /// `lines` is a JSON array of 1-based line numbers, e.g. `[3,12]`.
    static func setBookmarksJavaScript(linesJSONArray: String) -> String {
        "\(jsGlobal) && \(jsGlobal).setBookmarks && \(jsGlobal).setBookmarks(\(linesJSONArray));"
    }

    static func goToLineJavaScript(_ line: Int) -> String {
        "\(jsGlobal) && \(jsGlobal).goToLine && \(jsGlobal).goToLine(\(line));"
    }

    /// Run a named editor command (system context-menu / host actions).
    static func runCommandJavaScript(_ command: CodeMirrorCommand) -> String {
        let escaped = command.rawValue
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return "\(jsGlobal) && \(jsGlobal).runCommand && \(jsGlobal).runCommand('\(escaped)');"
    }
}
