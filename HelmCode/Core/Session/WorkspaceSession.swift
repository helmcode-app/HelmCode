//
//  WorkspaceSession.swift
//  HelmCode
//
//  Open project / file selection, recents, and editor surface routing.
//  Tree · bookmarks · source control live in WorkspaceSession+*.swift.
//

import Combine
import Foundation

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var projects: [WorkspaceProject]
    @Published var selectedProjectID: WorkspaceProject.ID?
    @Published var selectedFileID: WorkspaceNode.ID?
    /// Mutated only by session (recents / open project).
    @Published var recentProjectIDs: [WorkspaceProject.ID]
    /// Bookmarks across projects (persisted). Mutated in `WorkspaceSession+Bookmarks`.
    @Published var bookmarks: [WorkspaceBookmark]
    /// SCM state for the open project (`nil` when none open). Mutated in `+SourceControl`.
    @Published var sourceControl: SourceControlState?
    /// Transient error for sidebar alerts.
    @Published var lastTreeError: String?
    /// After opening a bookmark / search hit, editor scrolls to this 1-based line once.
    @Published var pendingEditorRevealLine: Int?

    let defaults: UserDefaults
    let recentLimit = 12
    /// SCM cache keyed by project so reopening restores working-tree status.
    var sourceControlByProject: [WorkspaceProject.ID: SourceControlState] = [:]

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
        if let node = project.root.find(id: id) { return node }
        // Tree refresh / atomic save can briefly omit a path; keep the editor open
        // via a stable synthetic node (`vfs:relative/path` ids).
        guard let path = WorkspaceNode.pathFromVFSNodeID(id) else { return nil }
        if let byPath = project.root.find(path: path) { return byPath }
        return WorkspaceNode.vfsPlaceholder(path: path, id: id)
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

    // MARK: - Project lifecycle

    func openProject(_ id: WorkspaceProject.ID) {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        selectedProjectID = id
        selectedFileID = nil
        pendingEditorRevealLine = nil
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
        pendingEditorRevealLine = nil
    }

    func openFile(_ id: WorkspaceNode.ID, revealLine: Int? = nil) {
        selectedFileID = id
        pendingEditorRevealLine = revealLine.map { max(1, $0) }
    }

    func consumePendingRevealLine() -> Int? {
        let line = pendingEditorRevealLine
        pendingEditorRevealLine = nil
        return line
    }

    func removeFromRecents(_ id: WorkspaceProject.ID) {
        recentProjectIDs.removeAll { $0 == id }
        persistRecent()
    }

    // MARK: - Shared helpers (used by +Tree / +Bookmarks / +SourceControl)

    func replaceOpenProject(_ project: WorkspaceProject) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
    }

    func collectIDs(in node: WorkspaceNode) -> Set<WorkspaceNode.ID> {
        var ids: Set<WorkspaceNode.ID> = [node.id]
        for child in node.children {
            ids.formUnion(collectIDs(in: child))
        }
        return ids
    }

    func recordRecent(_ id: WorkspaceProject.ID) {
        var next = recentProjectIDs.filter { $0 != id }
        next.insert(id, at: 0)
        if next.count > recentLimit {
            next = Array(next.prefix(recentLimit))
        }
        recentProjectIDs = next
        persistRecent()
    }

    func persistRecent() {
        defaults.set(recentProjectIDs.joined(separator: ","), forKey: AppStorageKey.recentProjectIDs)
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

    static func loadBookmarks(from defaults: UserDefaults) -> [WorkspaceBookmark] {
        guard let data = defaults.data(forKey: AppStorageKey.workspaceBookmarks),
              let decoded = try? JSONDecoder().decode([WorkspaceBookmark].self, from: data) else {
            return []
        }
        return decoded
    }
}
