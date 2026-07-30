//
//  WorkspaceSession+SourceControl.swift
//  HelmCode
//
//  Local mock SCM: stage / commit / pull·push·fetch + tree-edit bookkeeping.
//

import Foundation

@MainActor
extension WorkspaceSession {
    func stageChange(path: String) {
        updateSourceControl { state in
            guard let i = state.changes.firstIndex(where: { $0.path == path }) else { return }
            state.changes[i].isStaged = true
            state.lastMessage = "Staged \(state.changes[i].fileName)"
        }
    }

    func unstageChange(path: String) {
        updateSourceControl { state in
            guard let i = state.changes.firstIndex(where: { $0.path == path }) else { return }
            state.changes[i].isStaged = false
            state.lastMessage = "Unstaged \(state.changes[i].fileName)"
        }
    }

    func stageAll() {
        updateSourceControl { state in
            for i in state.changes.indices { state.changes[i].isStaged = true }
            state.lastMessage = "Staged all changes"
        }
    }

    func unstageAll() {
        updateSourceControl { state in
            for i in state.changes.indices { state.changes[i].isStaged = false }
            state.lastMessage = "Unstaged all changes"
        }
    }

    func discardChange(path: String) {
        updateSourceControl { state in
            state.changes.removeAll { $0.path == path }
            state.lastMessage = "Discarded \(path)"
        }
    }

    func commitStaged(message: String) {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else {
            lastTreeError = "Enter a commit message."
            return
        }
        updateSourceControl { state in
            let stagedCount = state.changes.filter(\.isStaged).count
            guard stagedCount > 0 else {
                state.lastMessage = "Nothing staged to commit"
                return
            }
            state.changes.removeAll { $0.isStaged }
            state.lastMessage = "Committed \(stagedCount) change(s): \(msg)"
        }
    }

    func pull() {
        updateSourceControl { state in
            state.lastMessage = "Pull from \(state.upstream ?? "origin") — simulated (no remote)."
        }
    }

    func push() {
        updateSourceControl { state in
            state.lastMessage = "Push to \(state.upstream ?? "origin") — simulated (no remote)."
        }
    }

    func fetch() {
        updateSourceControl { state in
            state.lastMessage = "Fetch completed — simulated."
        }
    }

    // MARK: - Bookkeeping from tree edits

    func noteCreate(_ node: WorkspaceNode) {
        guard !node.isDirectory else { return }
        updateSourceControl { state in
            upsertChange(
                &state,
                path: node.path,
                kind: .untracked,
                nodeID: node.id,
                preferStaged: false
            )
        }
    }

    func noteRename(from previousPath: String, to node: WorkspaceNode) {
        updateSourceControl { state in
            if let idx = state.changes.firstIndex(where: { $0.path == previousPath }) {
                var change = state.changes[idx]
                change.path = node.path
                change.nodeID = node.id
                if change.kind != .added && change.kind != .untracked {
                    change.kind = .modified
                }
                state.changes[idx] = change
            } else if !node.isDirectory {
                upsertChange(&state, path: node.path, kind: .modified, nodeID: node.id, preferStaged: false)
            }
            // Nested files under a renamed directory: re-key by prefix.
            if node.isDirectory {
                let prefix = previousPath + "/"
                for i in state.changes.indices where state.changes[i].path.hasPrefix(prefix) {
                    let suffix = String(state.changes[i].path.dropFirst(prefix.count))
                    state.changes[i].path = node.path + "/" + suffix
                }
            }
        }
    }

    func noteDelete(_ removed: WorkspaceNode) {
        updateSourceControl { state in
            let files = removed.collectAllFiles()
            if files.isEmpty, !removed.isDirectory {
                applyDelete(&state, path: removed.path, nodeID: removed.id)
            } else {
                for file in files {
                    applyDelete(&state, path: file.path, nodeID: file.id)
                }
                if removed.isDirectory {
                    let prefix = removed.path + "/"
                    state.changes.removeAll {
                        $0.path == removed.path || $0.path.hasPrefix(prefix)
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func updateSourceControl(_ body: (inout SourceControlState) -> Void) {
        guard let projectID = selectedProjectID else { return }
        var state = sourceControl ?? sourceControlByProject[projectID] ?? SourceControlState(
            branch: selectedProject?.defaultBranch ?? "main",
            upstream: nil,
            changes: [],
            lastMessage: nil
        )
        body(&state)
        sourceControl = state
        sourceControlByProject[projectID] = state
    }

    private func applyDelete(_ state: inout SourceControlState, path: String, nodeID: WorkspaceNode.ID?) {
        if let idx = state.changes.firstIndex(where: { $0.path == path || $0.nodeID == nodeID }) {
            if state.changes[idx].kind == .added || state.changes[idx].kind == .untracked {
                state.changes.remove(at: idx)
            } else {
                state.changes[idx].kind = .deleted
                state.changes[idx].path = path
                state.changes[idx].nodeID = nil
                state.changes[idx].isStaged = false
            }
        } else {
            state.changes.append(
                GitChange(path: path, kind: .deleted, nodeID: nil, isStaged: false)
            )
        }
    }

    private func upsertChange(
        _ state: inout SourceControlState,
        path: String,
        kind: GitChangeKind,
        nodeID: WorkspaceNode.ID?,
        preferStaged: Bool
    ) {
        if let idx = state.changes.firstIndex(where: { $0.path == path }) {
            state.changes[idx].kind = kind
            state.changes[idx].nodeID = nodeID
            if preferStaged { state.changes[idx].isStaged = true }
        } else {
            state.changes.append(
                GitChange(path: path, kind: kind, nodeID: nodeID, isStaged: preferStaged)
            )
        }
    }
}
