//
//  VFSPath.swift
//  HelmCode
//
//  Relative VFS path helpers shared by session, editor, and tree refresh.
//

import Foundation

enum VFSPath {
    /// Strip leading/trailing slashes for stable comparisons.
    static func normalize(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// True when two relative (or lightly prefixed) paths refer to the same file.
    static func matches(_ a: String, _ b: String) -> Bool {
        normalize(a) == normalize(b)
    }

    /// Path component after the last `/` (or the whole path).
    static func fileName(of path: String) -> String {
        let trimmed = normalize(path)
        guard let slash = trimmed.lastIndex(of: "/") else { return trimmed }
        return String(trimmed[trimmed.index(after: slash)...])
    }

    /// Parent directory of a relative path (`""` at the workspace root).
    static func directory(of path: String) -> String {
        let trimmed = normalize(path)
        guard let slash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[..<slash])
    }
}
