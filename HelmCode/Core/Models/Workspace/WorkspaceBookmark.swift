//
//  WorkspaceBookmark.swift
//  HelmCode
//
//  Two kinds:
//  • File/folder bookmark — whole node (`line == nil`), from sidebar context menu
//  • Line bookmark — 1-based line inside a file, from the editor (Xcode-style)
//

import Foundation

struct WorkspaceBookmark: Identifiable, Hashable, Codable, Sendable {
    let projectID: WorkspaceProject.ID
    let nodeID: WorkspaceNode.ID
    /// `nil` = entire file/folder; otherwise 1-based line in a file.
    let line: Int?
    /// Optional snapshot of the line text when bookmarked (line bookmarks only).
    var lineText: String?

    var id: String {
        if let line {
            return "\(projectID)|\(nodeID)|L\(line)"
        }
        return "\(projectID)|\(nodeID)|file"
    }

    /// Whole-node bookmark (sidebar).
    var isFileBookmark: Bool { line == nil }

    /// Line bookmark (editor).
    var isLineBookmark: Bool { line != nil }

    init(
        projectID: WorkspaceProject.ID,
        nodeID: WorkspaceNode.ID,
        line: Int? = nil,
        lineText: String? = nil
    ) {
        self.projectID = projectID
        self.nodeID = nodeID
        if let line {
            self.line = max(1, line)
            self.lineText = lineText
        } else {
            self.line = nil
            self.lineText = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case projectID, nodeID, line, lineText
    }

    /// Missing `line` → whole-file bookmark (original format).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try c.decode(String.self, forKey: .projectID)
        nodeID = try c.decode(String.self, forKey: .nodeID)
        if let line = try c.decodeIfPresent(Int.self, forKey: .line) {
            self.line = max(1, line)
            lineText = try c.decodeIfPresent(String.self, forKey: .lineText)
        } else {
            line = nil
            lineText = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(projectID, forKey: .projectID)
        try c.encode(nodeID, forKey: .nodeID)
        try c.encodeIfPresent(line, forKey: .line)
        try c.encodeIfPresent(lineText, forKey: .lineText)
    }
}
