//
//  CodeMirrorBundle.swift
//  HelmCode
//
//  Resolves bundled CodeMirror host assets (index.html + editor.bundle.js).
//

import Foundation

enum CodeMirrorBundle {
    /// Message handler name registered on the WKWebView bridge.
    static let messageHandlerName = "helmEditor"

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
}
