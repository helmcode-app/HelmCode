//
//  WorkspaceSession.swift
//  HelmCode
//
//  Workspace selection, tree edits, bookmarks, and sidebar source control.
//

import Combine
import Foundation

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var projects: [WorkspaceProject]
    @Published var selectedProjectID: WorkspaceProject.ID?
    @Published var selectedFileID: WorkspaceNode.ID?
    @Published private(set) var recentProjectIDs: [WorkspaceProject.ID]
    /// Bookmarks across projects (persisted).
    @Published private(set) var bookmarks: [WorkspaceBookmark]
    /// SCM state for the open project (`nil` when none open).
    @Published private(set) var sourceControl: SourceControlState?
    /// Transient error for sidebar alerts.
    @Published var lastTreeError: String?

    private let defaults: UserDefaults
    private let recentLimit = 12
    /// SCM cache keyed by project so reopening restores working tree status.
    private var sourceControlByProject: [WorkspaceProject.ID: SourceControlState] = [:]

    init(
        projects: [WorkspaceProject]? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolved = projects ?? WorkspaceCatalog.projects
        self.projects = resolved
        self.defaults = defaults
        self.selectedProjectID = nil
        self.selectedFileID = nil
        self.recentProjectIDs = Self.loadRecentIDs(from: defaults, known: resolved)
        self.bookmarks = Self.loadBookmarks(from: defaults)
        self.sourceControl = nil
    }

    // MARK: - Selection

    var selectedProject: WorkspaceProject? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedFile: WorkspaceNode? {
        guard let project = selectedProject, let id = selectedFileID else { return nil }
        return project.root.find(id: id)
    }

    var editorSurface: EditorSurface {
        guard let project = selectedProject else { return .welcome }
        if let file = selectedFile, !file.isDirectory {
            return .editing(project: project, file: file)
        }
        return .emptyProject(project)
    }

    var recentProjects: [WorkspaceProject] {
        recentProjectIDs.compactMap { id in projects.first { $0.id == id } }
    }

    /// Bookmarks that still resolve in the open project.
    var activeBookmarks: [(bookmark: WorkspaceBookmark, node: WorkspaceNode)] {
        guard let project = selectedProject else { return [] }
        return bookmarks.compactMap { mark in
            guard mark.projectID == project.id,
                  let node = project.root.find(id: mark.nodeID) else { return nil }
            return (mark, node)
        }
    }

    func isBookmarked(_ nodeID: WorkspaceNode.ID) -> Bool {
        guard let projectID = selectedProjectID else { return false }
        return bookmarks.contains { $0.projectID == projectID && $0.nodeID == nodeID }
    }

    // MARK: - Project lifecycle

    func openProject(_ id: WorkspaceProject.ID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        selectedProjectID = id
        selectedFileID = nil
        recordRecent(id)
        if sourceControlByProject[id] == nil {
            sourceControlByProject[id] = SourceControlState.seed(for: project)
        }
        sourceControl = sourceControlByProject[id]
        pruneBookmarks(for: project)
    }

    func closeProject() {
        if let id = selectedProjectID, let sc = sourceControl {
            sourceControlByProject[id] = sc
        }
        selectedProjectID = nil
        selectedFileID = nil
        sourceControl = nil
    }

    func openFile(_ id: WorkspaceNode.ID) {
        selectedFileID = id
    }

    func removeFromRecents(_ id: WorkspaceProject.ID) {
        recentProjectIDs.removeAll { $0 == id }
        persistRecent()
    }

    // MARK: - Tree operations

    @discardableResult
    func createFile(named rawName: String, relativeTo anchorID: WorkspaceNode.ID?) -> WorkspaceNode? {
        createNode(named: rawName, isDirectory: false, relativeTo: anchorID)
    }

    @discardableResult
    func createFolder(named rawName: String, relativeTo anchorID: WorkspaceNode.ID?) -> WorkspaceNode? {
        createNode(named: rawName, isDirectory: true, relativeTo: anchorID)
    }

    @discardableResult
    func renameNode(id: WorkspaceNode.ID, to rawName: String) -> WorkspaceNode? {
        guard var project = selectedProject else { return nil }
        let previousPath = project.root.find(id: id)?.path
        switch project.root.renaming(id: id, to: rawName) {
        case .failure(let error):
            lastTreeError = error.localizedDescription
            return nil
        case .success(let result):
            project = project.withRoot(result.tree)
            replaceOpenProject(project)
            if let previousPath {
                noteRename(from: previousPath, to: result.node)
            }
            lastTreeError = nil
            return result.node
        }
    }

    @discardableResult
    func deleteNode(id: WorkspaceNode.ID) -> Bool {
        guard var project = selectedProject else { return false }
        switch project.root.removing(id: id) {
        case .failure(let error):
            lastTreeError = error.localizedDescription
            return false
        case .success(let result):
            project = project.withRoot(result.tree)
            replaceOpenProject(project)
            if let sel = selectedFileID, project.root.find(id: sel) == nil {
                selectedFileID = nil
            }
            noteDelete(result.removed)
            removeBookmarks(nodeIDs: collectIDs(in: result.removed), projectID: project.id)
            lastTreeError = nil
            return true
        }
    }

    // MARK: - Bookmarks

    func toggleBookmark(nodeID: WorkspaceNode.ID) {
        guard let projectID = selectedProjectID,
              let project = selectedProject,
              project.root.contains(id: nodeID) else { return }

        if let idx = bookmarks.firstIndex(where: { $0.projectID == projectID && $0.nodeID == nodeID }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.insert(WorkspaceBookmark(projectID: projectID, nodeID: nodeID), at: 0)
        }
        persistBookmarks()
    }

    func removeBookmark(_ bookmark: WorkspaceBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persistBookmarks()
    }

    // MARK: - Source control

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

    // MARK: - Private tree helpers

    private func createNode(
        named rawName: String,
        isDirectory: Bool,
        relativeTo anchorID: WorkspaceNode.ID?
    ) -> WorkspaceNode? {
        guard var project = selectedProject else { return nil }
        guard let name = WorkspaceNode.sanitizeName(rawName) else {
            lastTreeError = WorkspaceTreeError.invalidName.localizedDescription
            return nil
        }
        let parentID = project.root.insertionParentID(for: anchorID)
        guard let parent = project.root.find(id: parentID) else {
            lastTreeError = WorkspaceTreeError.notFound.localizedDescription
            return nil
        }
        let node = isDirectory
            ? WorkspaceNode.makeDirectory(name: name, parentPath: parent.path)
            : WorkspaceNode.makeFile(name: name, parentPath: parent.path)

        switch project.root.inserting(node, under: parentID) {
        case .failure(let error):
            lastTreeError = error.localizedDescription
            return nil
        case .success(let tree):
            project = project.withRoot(tree)
            replaceOpenProject(project)
            noteCreate(node)
            if !isDirectory {
                selectedFileID = node.id
            }
            lastTreeError = nil
            return node
        }
    }

    private func replaceOpenProject(_ project: WorkspaceProject) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
    }

    private func collectIDs(in node: WorkspaceNode) -> Set<WorkspaceNode.ID> {
        var ids: Set<WorkspaceNode.ID> = [node.id]
        for child in node.children {
            ids.formUnion(collectIDs(in: child))
        }
        return ids
    }

    // MARK: - SCM bookkeeping

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

    private func noteCreate(_ node: WorkspaceNode) {
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

    private func noteRename(from previousPath: String, to node: WorkspaceNode) {
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

    private func noteDelete(_ removed: WorkspaceNode) {
        updateSourceControl { state in
            let files = removed.collectAllFiles()
            if files.isEmpty, !removed.isDirectory {
                applyDelete(&state, path: removed.path, nodeID: removed.id)
            } else {
                for file in files {
                    applyDelete(&state, path: file.path, nodeID: file.id)
                }
                if removed.isDirectory {
                    // Drop any leftover paths under the directory.
                    let prefix = removed.path + "/"
                    state.changes.removeAll {
                        $0.path == removed.path || $0.path.hasPrefix(prefix)
                    }
                }
            }
        }
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

    // MARK: - Persistence

    private func recordRecent(_ id: WorkspaceProject.ID) {
        var next = recentProjectIDs.filter { $0 != id }
        next.insert(id, at: 0)
        if next.count > recentLimit {
            next = Array(next.prefix(recentLimit))
        }
        recentProjectIDs = next
        persistRecent()
    }

    private func persistRecent() {
        defaults.set(recentProjectIDs.joined(separator: ","), forKey: AppStorageKey.recentProjectIDs)
    }

    private func persistBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        defaults.set(data, forKey: AppStorageKey.workspaceBookmarks)
    }

    private func removeBookmarks(nodeIDs: Set<WorkspaceNode.ID>, projectID: WorkspaceProject.ID) {
        let before = bookmarks.count
        bookmarks.removeAll { $0.projectID == projectID && nodeIDs.contains($0.nodeID) }
        if bookmarks.count != before { persistBookmarks() }
    }

    private func pruneBookmarks(for project: WorkspaceProject) {
        let before = bookmarks.count
        bookmarks.removeAll { mark in
            mark.projectID == project.id && project.root.find(id: mark.nodeID) == nil
        }
        if bookmarks.count != before { persistBookmarks() }
    }

    private static func loadRecentIDs(
        from defaults: UserDefaults,
        known projects: [WorkspaceProject]
    ) -> [WorkspaceProject.ID] {
        let knownIDs = Set(projects.map(\.id))
        if let raw = defaults.string(forKey: AppStorageKey.recentProjectIDs), !raw.isEmpty {
            let parsed = raw.split(separator: ",").map(String.init).filter { knownIDs.contains($0) }
            if !parsed.isEmpty { return parsed }
        }
        return projects.map(\.id)
    }

    private static func loadBookmarks(from defaults: UserDefaults) -> [WorkspaceBookmark] {
        guard let data = defaults.data(forKey: AppStorageKey.workspaceBookmarks),
              let decoded = try? JSONDecoder().decode([WorkspaceBookmark].self, from: data) else {
            return []
        }
        return decoded
    }
}
