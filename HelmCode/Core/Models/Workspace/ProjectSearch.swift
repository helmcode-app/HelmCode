//
//  ProjectSearch.swift
//  HelmCode
//
//  In-project text search over workspace files (sample buffers until real FS).
//

import Foundation

struct ProjectSearchMatch: Identifiable, Hashable, Sendable {
    let id: String
    let nodeID: WorkspaceNode.ID
    let path: String
    let fileName: String
    let line: Int
    /// 0-based UTF-16 offset of the first match on the line (for future highlight).
    let column: Int
    let lineText: String
    let languageHint: String?

    init(
        nodeID: WorkspaceNode.ID,
        path: String,
        fileName: String,
        line: Int,
        column: Int,
        lineText: String,
        languageHint: String?
    ) {
        self.id = "\(nodeID)|\(line)|\(column)|\(path)"
        self.nodeID = nodeID
        self.path = path
        self.fileName = fileName
        self.line = line
        self.column = column
        self.lineText = lineText
        self.languageHint = languageHint
    }
}

struct ProjectSearchFileGroup: Identifiable, Hashable, Sendable {
    var id: WorkspaceNode.ID { nodeID }
    let nodeID: WorkspaceNode.ID
    let path: String
    let fileName: String
    let languageHint: String?
    let matches: [ProjectSearchMatch]
}

enum ProjectSearch {
    /// Cap results so large trees stay responsive in the sidebar.
    static let maxMatches = 200
    static let maxFiles = 500

    static func search(
        project: WorkspaceProject,
        query: String,
        caseSensitive: Bool = false,
        matchWholeWord: Bool = false
    ) -> [ProjectSearchFileGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let files = project.root.collectAllFiles(limit: maxFiles)
        var groups: [ProjectSearchFileGroup] = []
        var total = 0

        for file in files {
            if total >= maxMatches { break }
            let content = EditorSampleLibrary.content(for: file.path, project: project.name)
            let fileMatches = matchInContent(
                content,
                query: trimmed,
                caseSensitive: caseSensitive,
                matchWholeWord: matchWholeWord,
                node: file,
                remaining: maxMatches - total
            )
            guard !fileMatches.isEmpty else { continue }
            total += fileMatches.count
            groups.append(
                ProjectSearchFileGroup(
                    nodeID: file.id,
                    path: file.path,
                    fileName: file.name,
                    languageHint: file.languageHint,
                    matches: fileMatches
                )
            )
        }

        return groups
    }

    private static func matchInContent(
        _ content: String,
        query: String,
        caseSensitive: Bool,
        matchWholeWord: Bool,
        node: WorkspaceNode,
        remaining: Int
    ) -> [ProjectSearchMatch] {
        guard remaining > 0 else { return [] }
        var results: [ProjectSearchMatch] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let compareOptions: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

        for (index, lineSub) in lines.enumerated() {
            if results.count >= remaining { break }
            let lineText = String(lineSub)
            let haystack = lineText
            let needle = query

            var searchRange = haystack.startIndex..<haystack.endIndex
            while results.count < remaining,
                  let found = haystack.range(
                    of: needle,
                    options: compareOptions,
                    range: searchRange
                  ) {
                if matchWholeWord, !isWholeWord(in: haystack, match: found) {
                    searchRange = found.upperBound..<haystack.endIndex
                    if searchRange.isEmpty { break }
                    continue
                }

                let column = haystack.utf16.distance(from: haystack.startIndex, to: found.lowerBound)
                results.append(
                    ProjectSearchMatch(
                        nodeID: node.id,
                        path: node.path,
                        fileName: node.name,
                        line: index + 1,
                        column: column,
                        lineText: lineText.trimmingCharacters(in: .whitespaces),
                        languageHint: node.languageHint
                    )
                )
                // One match per line is enough for sidebar (VS Code often shows one row per line).
                break
            }
        }
        return results
    }

    private static func isWholeWord(in string: String, match: Range<String.Index>) -> Bool {
        let beforeOK: Bool = {
            guard match.lowerBound > string.startIndex else { return true }
            let prev = string.index(before: match.lowerBound)
            return !string[prev].isLetter && !string[prev].isNumber && string[prev] != "_"
        }()
        let afterOK: Bool = {
            guard match.upperBound < string.endIndex else { return true }
            let next = string[match.upperBound]
            return !next.isLetter && !next.isNumber && next != "_"
        }()
        return beforeOK && afterOK
    }
}

extension WorkspaceNode {
    /// All files under this node (no artificial small limit for search).
    func collectAllFiles(limit: Int = 10_000) -> [WorkspaceNode] {
        collectFiles(limit: limit)
    }
}
