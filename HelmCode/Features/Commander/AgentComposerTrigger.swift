//
//  AgentComposerTrigger.swift
//  HelmCode
//
//  Detect `/skills` and `@file` tokens at the composer caret.
//

import SwiftUI

enum AgentComposerTriggerKind: String, Equatable {
    case slash
    case mention

    var menuTitle: String {
        switch self {
        case .slash: return "Skills"
        case .mention: return "Files"
        }
    }

    var emptyCopy: String {
        switch self {
        case .slash: return "No matching skills"
        case .mention: return "No matching files"
        }
    }
}

/// Active `/query` or `@query` at the caret (whitespace-bounded).
struct AgentComposerTrigger: Equatable {
    var kind: AgentComposerTriggerKind
    var query: String
    /// UTF-16 location of the trigger token in the prompt.
    var utf16Range: NSRange

    /// Identity for resetting menu highlight as the user types.
    var menuIdentity: String { "\(kind.rawValue):\(query)" }

    func range(in text: String) -> Range<String.Index>? {
        Range(utf16Range, in: text)
    }

    static func detect(in text: String, selection: TextSelection?) -> AgentComposerTrigger? {
        guard AgentPromptEditing.isCollapsed(selection) else { return nil }
        let caret = AgentPromptEditing.insertionIndex(in: text, selection: selection)
        var start = caret
        while start > text.startIndex {
            let prev = text.index(before: start)
            let ch = text[prev]
            if ch.isWhitespace || ch.isNewline { break }
            start = prev
        }
        guard start < caret else { return nil }
        let token = text[start..<caret]
        guard let first = token.first else { return nil }
        let kind: AgentComposerTriggerKind
        if first == "@" {
            kind = .mention
        } else if first == "/" {
            kind = .slash
        } else {
            return nil
        }
        return AgentComposerTrigger(
            kind: kind,
            query: String(token.dropFirst()),
            utf16Range: NSRange(start..<caret, in: text)
        )
    }
}
