//
//  WorkspaceSession+Persistence.swift
//  HelmCode
//
//  UserDefaults load/save for projects, recents, and last selection.
//

import Foundation

extension WorkspaceSession {
    func persistRecent() {
        defaults.set(recentProjectIDs.joined(separator: ","), forKey: AppStorageKey.recentProjectIDs)
    }

    func persistProjects() {
        guard !isRestoring else { return }
        let records = projects.compactMap { SavedProjectRecord(project: $0) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: AppStorageKey.savedProjects)
    }

    func persistEnrolledRunners() {
        guard !isRestoring else { return }
        guard let data = try? JSONEncoder().encode(enrolledRunners) else { return }
        defaults.set(data, forKey: AppStorageKey.enrolledRunners)
    }

    func persistLastSelectedProjectID() {
        guard !isRestoring else { return }
        if let id = selectedProjectID {
            defaults.set(id, forKey: AppStorageKey.lastSelectedProjectID)
        } else {
            defaults.removeObject(forKey: AppStorageKey.lastSelectedProjectID)
        }
    }

    static func loadSavedProjects(from defaults: UserDefaults) -> [WorkspaceProject] {
        guard let data = defaults.data(forKey: AppStorageKey.savedProjects),
              let records = try? JSONDecoder().decode([SavedProjectRecord].self, from: data) else {
            return []
        }
        return records.compactMap { record in
            guard RunnerURL.isValid(record.runnerBaseURL) else { return nil }
            return record.asWorkspaceProject()
        }
    }

    static func loadRecentIDs(
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

    static func loadEnrolledRunners(
        from defaults: UserDefaults,
        projects: [WorkspaceProject]
    ) -> [EnrolledRunner] {
        var stored: [EnrolledRunner] = []
        if let data = defaults.data(forKey: AppStorageKey.enrolledRunners),
           let decoded = try? JSONDecoder().decode([EnrolledRunner].self, from: data) {
            stored = decoded.filter { RunnerURL.isValid($0.url) && !$0.id.isEmpty }
        }
        for project in projects {
            guard let runnerId = project.runnerId,
                  let url = project.normalizedRunnerURL,
                  !stored.contains(where: { $0.id == runnerId || $0.url == url }) else { continue }
            stored.append(EnrolledRunner(id: runnerId, url: url, label: EnrolledRunner.hostLabel(for: url)))
        }
        return stored
    }

    static func loadBookmarks(from defaults: UserDefaults) -> [WorkspaceBookmark] {
        guard let data = defaults.data(forKey: AppStorageKey.workspaceBookmarks),
              let decoded = try? JSONDecoder().decode([WorkspaceBookmark].self, from: data) else {
            return []
        }
        return decoded
    }
}
