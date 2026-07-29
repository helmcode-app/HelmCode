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

    static var relayoutJavaScript: String {
        "\(jsGlobal) && \(jsGlobal).relayout && \(jsGlobal).relayout();"
    }
}
