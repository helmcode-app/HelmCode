//
//  TerminalBundle.swift
//  HelmCode
//
//  Offline xterm.js WebSSH assets + JS bridge identifiers.
//

import Foundation

enum TerminalBundle {
    /// `WKScriptMessageHandler` name (must match terminal-entry postMessage).
    static let messageHandlerName = "helmTerminal"

    /// Global installed by `terminal.bundle.js`.
    static let jsGlobal = "window.HelmTerminal"

    /// Locates `terminal.html` (unique name — avoids clashing with CodeMirror `index.html`).
    static func indexHTMLURL(in bundle: Bundle = .main) -> URL? {
        let candidates: [URL?] = [
            bundle.url(forResource: "terminal", withExtension: "html"),
            bundle.url(forResource: "terminal", withExtension: "html", subdirectory: "Terminal"),
            bundle.url(
                forResource: "terminal",
                withExtension: "html",
                subdirectory: "Features/Editor/Terminal"
            ),
        ]
        return candidates.compactMap { $0 }.first
    }

    static func configureJavaScript(
        baseURL: String,
        ticket: String,
        workspaceId: String = HelmWorkspace.defaultID
    ) -> String {
        call("configure", argsObject: connectionArgs(baseURL: baseURL, ticket: ticket, workspaceId: workspaceId))
    }

    static func connectJavaScript(
        baseURL: String,
        ticket: String,
        workspaceId: String = HelmWorkspace.defaultID
    ) -> String {
        call("connect", argsObject: connectionArgs(baseURL: baseURL, ticket: ticket, workspaceId: workspaceId))
    }

    static var disconnectJavaScript: String { call("disconnect") }
    /// Drop socket + wipe scrollback (project switch / close).
    static var resetSessionJavaScript: String { call("resetSession") }
    static var fitJavaScript: String { call("fit") }
    static var focusJavaScript: String { call("focus") }
    static var clearJavaScript: String { call("clear") }

    static func sendInputJavaScript(_ data: String) -> String {
        call("sendInput", rawArgs: JSONFragment.string(data))
    }

    static func setFontSizeJavaScript(_ size: Int) -> String {
        call("setFontSize", rawArgs: "\(size)")
    }

    static var getSelectionTextJavaScript: String {
        "\(jsGlobal) && \(jsGlobal).getSelectionText ? \(jsGlobal).getSelectionText() : ''"
    }

    static func getBufferSnippetJavaScript(maxLines: Int = 40) -> String {
        "\(jsGlobal) && \(jsGlobal).getBufferSnippet ? \(jsGlobal).getBufferSnippet(\(maxLines)) : ''"
    }

    static func findNextJavaScript(query: String, incremental: Bool = false) -> String {
        "\(jsGlobal) && \(jsGlobal).findNext && \(jsGlobal).findNext(\(JSONFragment.string(query)), { incremental: \(incremental) });"
    }

    static func findPreviousJavaScript(query: String) -> String {
        "\(jsGlobal) && \(jsGlobal).findPrevious && \(jsGlobal).findPrevious(\(JSONFragment.string(query)));"
    }

    static var clearSearchJavaScript: String {
        call("clearSearch")
    }

    /// Apply light/dark xterm theme to match editor `systemBackground`.
    static func setColorSchemeJavaScript(isDark: Bool) -> String {
        let scheme = JSONFragment.string(isDark ? "dark" : "light")
        return call("setColorScheme", rawArgs: scheme)
    }

    // MARK: - Private

    private static func connectionArgs(
        baseURL: String,
        ticket: String,
        workspaceId: String
    ) -> String {
        "{ baseURL: \(JSONFragment.string(baseURL)), ticket: \(JSONFragment.string(ticket)), workspaceId: \(JSONFragment.string(workspaceId)) }"
    }

    private static func call(_ method: String, argsObject: String? = nil, rawArgs: String? = nil) -> String {
        if let argsObject {
            return "\(jsGlobal) && \(jsGlobal).\(method) && \(jsGlobal).\(method)(\(argsObject));"
        }
        if let rawArgs {
            return "\(jsGlobal) && \(jsGlobal).\(method) && \(jsGlobal).\(method)(\(rawArgs));"
        }
        return "\(jsGlobal) && \(jsGlobal).\(method) && \(jsGlobal).\(method)();"
    }
}
