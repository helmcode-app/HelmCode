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
        let result = text
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
        let replaceRange = replacementRange(in: text, selection: selection)
        return apply(insertion, to: text, range: replaceRange)
    }

    /// Replace an explicit range (slash / mention token) and park the caret after it.
    static func replace(
        _ range: Range<String.Index>,
        with insertion: String,
        in text: String
    ) -> (text: String, selection: TextSelection) {
        guard let safe = clampedRange(range, in: text) else {
            return apply(insertion, to: text, range: text.endIndex..<text.endIndex)
        }
        return apply(insertion, to: text, range: safe)
    }

    /// Caret used by `/` and `@` token detection. Nil / stale selection → end of text.
    static func insertionIndex(in text: String, selection: TextSelection?) -> String.Index {
        replacementRange(in: text, selection: selection).upperBound
    }

    /// True when the editor has a caret rather than a highlighted range.
    /// Stale selections (from a previous prompt value) count as collapsed so callers
    /// fall through to a safe end-of-text caret instead of trapping on String.Index.
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
        let raw: Range<String.Index>? = {
            switch selection.indices {
            case .selection(let range):
                return range
            case .multiSelection(let ranges):
                return ranges.ranges.first
            @unknown default:
                return nil
            }
        }()
        guard let raw, let safe = clampedRange(raw, in: text) else {
            return end..<end
        }
        return safe
    }

    /// Drop selection ranges whose indices fall outside `text`.
    /// SwiftUI can keep a `TextSelection` alive across wholesale prompt clears
    /// (`prompt = ""` on send); using those indices traps in StringIndexValidation.
    private static func clampedRange(
        _ range: Range<String.Index>,
        in text: String
    ) -> Range<String.Index>? {
        let start = text.startIndex
        let end = text.endIndex
        // Offset compares are safe across string values; subscript / index(before:) are not.
        guard range.lowerBound >= start, range.upperBound <= end,
              range.lowerBound <= range.upperBound
        else { return nil }
        return range
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
