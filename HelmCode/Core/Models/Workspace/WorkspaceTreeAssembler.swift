//
//  WorkspaceTreeAssembler.swift
//  HelmCode
//
//  O(N) flat `RawFileNode` list → nested `WorkspaceNode` forest.
//

import Foundation

enum WorkspaceTreeAssembler {
    /// Synthetic root id wrapping the workspace forest (children = top-level entries).
    static let rootID = "vfs-root"

    /// Build a single root node whose `children` are the top-level paths.
    /// - Parameter entries: Flat list from `vfs/initialize` (dirs + files, relative paths).
    /// - Parameter rootPath: Server workspace root (absolute on the runner).
    static func assemble(
        entries: [RawFileNode],
        rootPath: String,
        rootName: String? = nil
    ) -> WorkspaceNode {
        final class Builder {
            let name: String
            let path: String
            let isDirectory: Bool
            var size: Int64
            var children: [String: Builder] = [:]

            init(name: String, path: String, isDirectory: Bool, size: Int64 = 0) {
                self.name = name
                self.path = path
                self.isDirectory = isDirectory
                self.size = size
            }

            func toNode() -> WorkspaceNode {
                let sorted = children.values.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory && !rhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return WorkspaceNode(
                    id: path.isEmpty ? WorkspaceTreeAssembler.rootID : "vfs:\(path)",
                    name: name,
                    path: path,
                    isDirectory: isDirectory,
                    children: sorted.map { $0.toNode() },
                    languageHint: isDirectory ? nil : FileLanguageHint.resolve(fileName: name),
                    size: isDirectory ? 0 : size
                )
            }
        }

        let displayName = rootName
            ?? URL(fileURLWithPath: rootPath).lastPathComponent.nilIfEmpty
            ?? "Workspace"

        let root = Builder(name: displayName, path: "", isDirectory: true)

        for entry in entries {
            let parts = entry.path
                .split(separator: "/")
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !parts.isEmpty else { continue }

            var parent = root
            var cumulative = ""

            for (index, part) in parts.enumerated() {
                let isLast = index == parts.count - 1
                cumulative = cumulative.isEmpty ? part : "\(cumulative)/\(part)"

                if let existing = parent.children[part] {
                    if isLast, !entry.isDirectory {
                        existing.size = entry.size
                    }
                    parent = existing
                    continue
                }

                let isDir = isLast ? entry.isDirectory : true
                let node = Builder(
                    name: part,
                    path: cumulative,
                    isDirectory: isDir,
                    size: isLast && !entry.isDirectory ? entry.size : 0
                )
                parent.children[part] = node
                parent = node
            }
        }

        return root.toNode()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
