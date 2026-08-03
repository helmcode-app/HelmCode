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
    static func insert(
        _ insertion: String,
        into text: String,
        selection: TextSelection?
    ) -> (text: String, selection: TextSelection) {
        var result = text
        let end = result.endIndex

        let replaceRange: Range<String.Index>
        if let selection {
            switch selection.indices {
            case .selection(let range):
                replaceRange = range
            case .multiSelection(let ranges):
                replaceRange = ranges.ranges.first ?? end..<end
            @unknown default:
                replaceRange = end..<end
            }
        } else {
            replaceRange = end..<end
        }

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

        result.replaceSubrange(replaceRange, with: piece)

        let caret: String.Index
        if let newEnd = result.index(
            replaceRange.lowerBound,
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
