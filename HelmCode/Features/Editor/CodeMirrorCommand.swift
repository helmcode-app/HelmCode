//
//  CodeMirrorCommand.swift
//  HelmCode
//
//  Named editor commands shared by the system context menu and JS bridge.
//  Keep ids in sync with `runCommand` in editor-entry.mjs.
//

import Foundation

/// Stable command ids for `window.HelmCodeEditor.runCommand(_:)`.
enum CodeMirrorCommand: String, CaseIterable, Sendable {
    case toggleComment
    case toggleBookmark
    case selectLine
    case find
    case indentMore
    case indentLess
    case deleteLine

    /// Items shown in the system edit / context menu (subset of all commands).
    static let contextMenuItems: [ContextMenuItem] = [
        .init(command: .toggleComment, title: "Toggle Comment", systemImage: "text.quote"),
        .init(command: .toggleBookmark, title: "Toggle Bookmark", systemImage: "bookmark"),
        .init(command: .selectLine, title: "Select Line", systemImage: "line.3.horizontal"),
        .init(command: .find, title: "Find", systemImage: "magnifyingglass"),
    ]

    struct ContextMenuItem: Sendable {
        let command: CodeMirrorCommand
        let title: String
        let systemImage: String
    }
}
