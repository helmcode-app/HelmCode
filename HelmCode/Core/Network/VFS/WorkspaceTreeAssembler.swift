//
//  WorkspaceTreeAssembler.swift
//  HelmCode
//
//  O(N) flat `RawFileNode` list → nested `WorkspaceTreeNode` forest.
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
    ) -> WorkspaceTreeNode {
        // path → mutable builder
        final class Builder {
            let name: String
            let path: String
            let isDirectory: Bool
            var size: Int64
            var children: [String: Builder] = [:]

            init(name: String, path: String, isDirectory: Bool, size: Int64) {
                self.name = name
                self.path = path
                self.isDirectory = isDirectory
                self.size = size
            }

            func toNode() -> WorkspaceTreeNode {
                let sorted = children.values.sorted { lhs, rhs in
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory && !rhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
                return WorkspaceTreeNode(
                    id: path.isEmpty ? WorkspaceTreeAssembler.rootID : "vfs:\(path)",
                    name: name,
                    path: path,
                    isDirectory: isDirectory,
                    size: size,
                    children: sorted.map { $0.toNode() }
                )
            }
        }

        let displayName = rootName
            ?? URL(fileURLWithPath: rootPath).lastPathComponent
            .nilIfEmpty
            ?? "Workspace"

        let root = Builder(name: displayName, path: "", isDirectory: true, size: 0)

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
                    if isLast {
                        // Prefer explicit dir/file flags and sizes from the leaf entry.
                        existing.size = entry.size
                    }
                    parent = existing
                    continue
                }

                let isDir: Bool
                if isLast {
                    isDir = entry.isDirectory
                } else {
                    isDir = true
                }

                let node = Builder(
                    name: part,
                    path: cumulative,
                    isDirectory: isDir,
                    size: isLast ? entry.size : 0
                )
                parent.children[part] = node
                parent = node
            }
        }

        return root.toNode()
    }

    /// Convenience: forest without a synthetic display root (top-level children only).
    static func topLevelForest(from entries: [RawFileNode], rootPath: String) -> [WorkspaceTreeNode] {
        assemble(entries: entries, rootPath: rootPath).children
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
