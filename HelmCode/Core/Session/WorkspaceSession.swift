//
//  WorkspaceSession.swift
//  HelmCode
//
//  Open project / file selection, recents, and editor surface routing.
//  Extensions: +Persistence · +Tree · +Bookmarks · +SourceControl · +VFS
//  Projects are created only via Open Project and persisted to disk.
//

import Combine
import Foundation

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var projects: [WorkspaceProject] {
        didSet { persistProjects() }
    }
    @Published var selectedProjectID: WorkspaceProject.ID? {
        didSet { persistLastSelectedProjectID() }
    }
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

    /// Skip disk writes while reconstructing state in `init` (`+Persistence`).
    var isRestoring = true

    init(
        projects: [WorkspaceProject]? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        let resolved = projects ?? Self.loadSavedProjects(from: defaults)
        self.projects = resolved
        self.selectedFileID = nil
        self.recentProjectIDs = Self.loadRecentIDs(from: defaults, known: resolved)
        self.bookmarks = Self.loadBookmarks(from: defaults)
        self.sourceControl = nil
        // Welcome first; project list stays cached from disk.
        self.selectedProjectID = nil
        self.isRestoring = false
    }

    // MARK: - Selection

    var selectedProject: WorkspaceProject? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    var selectedFile: WorkspaceNode? {
        guard let project = selectedProject, let id = selectedFileID else { return nil }
        if let node = project.root.find(id: id) { return node }
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
        } else if var sc = sourceControlByProject[id] {
            sc.applyBranch(from: project)
            sourceControlByProject[id] = sc
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

    /// Remove a saved project from the local catalog (and recents).
    func removeProject(_ id: WorkspaceProject.ID) {
        if selectedProjectID == id {
            closeProject()
        }
        projects.removeAll { $0.id == id }
        recentProjectIDs.removeAll { $0 == id }
        sourceControlByProject[id] = nil
        persistRecent()
        persistProjects()
    }

    /**
     Apply Project Settings: display name, runner URL, API token.
     Returns the resulting project id (may change when runner URL changes).
     */
    @discardableResult
    func updateProjectSettings(
        id: WorkspaceProject.ID,
        customName: String,
        runnerURL: String,
        apiToken: String
    ) throws -> WorkspaceProject.ID {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectSettingsError.projectNotFound
        }
        guard RunnerURL.isValid(runnerURL) else {
            throw ProjectSettingsError.invalidRunnerURL
        }

        let normalizedURL = RunnerURL.normalizeHTTP(runnerURL)
        let newID = WorkspaceProject.stableID(forRunnerBaseURL: normalizedURL)
        let current = projects[idx]
        let nameOverride = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        // Reject URL collision with a different project.
        if let other = projects.first(where: {
            $0.id != id && $0.normalizedRunnerURL == normalizedURL
        }) {
            throw ProjectSettingsError.runnerURLInUse(other.displayName)
        }

        let updated = WorkspaceProject(
            id: newID,
            name: current.name,
            remote: current.remote,
            defaultBranch: current.defaultBranch,
            root: current.root,
            runnerBaseURL: normalizedURL,
            customName: nameOverride.isEmpty ? nil : nameOverride,
            apiToken: token.isEmpty ? nil : token
        )

        let wasSelected = selectedProjectID == id
        projects[idx] = updated

        if newID != id {
            if let sc = sourceControlByProject[id] {
                sourceControlByProject[newID] = sc
                sourceControlByProject[id] = nil
            }
            recentProjectIDs = recentProjectIDs.map { $0 == id ? newID : $0 }
            if wasSelected {
                selectedProjectID = newID
            }
        }

        // Drop accidental duplicates by runner URL.
        var seen = Set<String>()
        projects = projects.filter { item in
            guard let url = item.normalizedRunnerURL else { return true }
            if seen.contains(url) { return item.id == newID }
            seen.insert(url)
            return true
        }

        RunnerConnectionPrefs.remember(url: normalizedURL, token: token)
        persistRecent()
        persistProjects()
        return newID
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
}
