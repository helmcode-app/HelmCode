//
//  WorkspaceSession.swift
//  HelmCode
//
//  Workspace selection: open project, open file, recent projects.
//  Starts with no project so the center column can show the welcome page.
//

import Combine
import Foundation

@MainActor
final class WorkspaceSession: ObservableObject {
    @Published var projects: [WorkspaceProject]
    /// `nil` → welcome / start page (no project open).
    @Published var selectedProjectID: WorkspaceProject.ID?
    @Published var selectedFileID: WorkspaceNode.ID?
    /// Most-recent first; persisted across launches.
    @Published private(set) var recentProjectIDs: [WorkspaceProject.ID]

    private let defaults: UserDefaults
    private let recentLimit = 12

    init(
        projects: [WorkspaceProject] = WorkspaceCatalog.projects,
        defaults: UserDefaults = .standard
    ) {
        self.projects = projects
        self.defaults = defaults
        self.selectedProjectID = nil
        self.selectedFileID = nil
        self.recentProjectIDs = Self.loadRecentIDs(from: defaults, known: projects)
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

    /// True when a project is open but no editable file is selected.
    var showsProjectEmptyState: Bool {
        guard selectedProject != nil else { return false }
        guard let file = selectedFile else { return true }
        return file.isDirectory
    }

    var recentProjects: [WorkspaceProject] {
        recentProjectIDs.compactMap { id in projects.first { $0.id == id } }
    }

    // MARK: - Actions

    func openProject(_ id: WorkspaceProject.ID) {
        guard projects.contains(where: { $0.id == id }) else { return }
        selectedProjectID = id
        selectedFileID = nil
        recordRecent(id)
    }

    func selectProject(_ id: WorkspaceProject.ID?) {
        if let id {
            openProject(id)
        } else {
            closeProject()
        }
    }

    func closeProject() {
        selectedProjectID = nil
        selectedFileID = nil
    }

    func openFile(_ id: WorkspaceNode.ID) {
        selectedFileID = id
    }

    func removeFromRecents(_ id: WorkspaceProject.ID) {
        recentProjectIDs.removeAll { $0 == id }
        persistRecent()
    }

    // MARK: - Recent persistence

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

    private static func loadRecentIDs(
        from defaults: UserDefaults,
        known projects: [WorkspaceProject]
    ) -> [WorkspaceProject.ID] {
        let knownIDs = Set(projects.map(\.id))
        if let raw = defaults.string(forKey: AppStorageKey.recentProjectIDs), !raw.isEmpty {
            let parsed = raw.split(separator: ",").map(String.init).filter { knownIDs.contains($0) }
            if !parsed.isEmpty { return parsed }
        }
        // First launch: seed recents from catalog order without opening any.
        return projects.map(\.id)
    }
}
