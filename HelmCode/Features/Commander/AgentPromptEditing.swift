//
//  AgentPromptEditing.swift
//  HelmCode
//
//  TextSelection-aware insertion helpers for the agent composer.
//

import SwiftUI

enum AgentPromptEditing {
    /// Insert `piece` at the caret (or replace the current selection).
    /// Returns the updated text and a selection with the caret after the insert.
    /// Pads with spaces around file tags so `@path` stays tokenized.
    static func insert(
        _ insertion: String,
        into text: String,
        selection: TextSelection?
    ) -> (text: String, selection: TextSelection) {
        var result = text
        let replaceRange = replacementRange(in: result, selection: selection)

        var piece = insertion
        if replaceRange.lowerBound > result.startIndex {
            let before = result[result.index(before: replaceRange.lowerBound)]
            if !before.isWhitespace {
                piece = " " + piece
            }
        }
        if replaceRange.upperBound < result.endIndex {
            let after = result[replaceRange.upperBound]
            if !after.isWhitespace {
                piece += " "
            }
        } else if replaceRange.lowerBound == result.endIndex, !result.isEmpty {
            let last = result[result.index(before: result.endIndex)]
            if !last.isWhitespace, !piece.hasPrefix(" ") {
                piece = " " + piece
            }
        }

        return apply(piece, to: result, range: replaceRange)
    }

    /// Insert without surrounding spaces (newlines, raw snippets).
    static func insertRaw(
        _ insertion: String,
        into text: String,
        selection: TextSelection?
    ) -> (text: String, selection: TextSelection) {
        var result = text
        let replaceRange = replacementRange(in: result, selection: selection)
        return apply(insertion, to: result, range: replaceRange)
    }

    /// Replace an explicit range (slash / mention token) and park the caret after it.
    static func replace(
        _ range: Range<String.Index>,
        with insertion: String,
        in text: String
    ) -> (text: String, selection: TextSelection) {
        apply(insertion, to: text, range: range)
    }

    /// Caret used by `/` and `@` token detection. Nil selection → end of text.
    static func insertionIndex(in text: String, selection: TextSelection?) -> String.Index {
        let end = text.endIndex
        guard let selection else { return end }
        switch selection.indices {
        case .selection(let range):
            return range.upperBound
        case .multiSelection(let ranges):
            return ranges.ranges.first?.upperBound ?? end
        @unknown default:
            return end
        }
    }

    /// True when the editor has a caret rather than a highlighted range.
    static func isCollapsed(_ selection: TextSelection?) -> Bool {
        guard let selection else { return true }
        switch selection.indices {
        case .selection(let range):
            return range.isEmpty
        case .multiSelection(let ranges):
            guard let first = ranges.ranges.first, ranges.ranges.count == 1 else {
                return false
            }
            return first.isEmpty
        @unknown default:
            return true
        }
    }

    private static func replacementRange(
        in text: String,
        selection: TextSelection?
    ) -> Range<String.Index> {
        let end = text.endIndex
        guard let selection else { return end..<end }
        switch selection.indices {
        case .selection(let range):
            return range
        case .multiSelection(let ranges):
            return ranges.ranges.first ?? end..<end
        @unknown default:
            return end..<end
        }
    }

    private static func apply(
        _ piece: String,
        to text: String,
        range: Range<String.Index>
    ) -> (text: String, selection: TextSelection) {
        var result = text
        result.replaceSubrange(range, with: piece)
        let caret: String.Index
        if let newEnd = result.index(
            range.lowerBound,
            offsetBy: piece.count,
            limitedBy: result.endIndex
        ) {
            caret = newEnd
        } else {
            caret = result.endIndex
        }
        return (result, TextSelection(insertionPoint: caret))
    }
}
