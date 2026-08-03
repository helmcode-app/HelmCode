//
//  WorkspaceSession+VFS.swift
//  HelmCode
//
//  Apply remote VFS tree / metadata into the open-project session model.
//

import Foundation

extension WorkspaceSession {
    /// Install / refresh a runner-backed project from a nested VFS tree.
    /// Identity is the runner base URL (stable across launches).
    func applyVFSTree(
        _ tree: WorkspaceNode,
        remoteRoot: String,
        gitRemote: String? = nil,
        gitBranch: String? = nil,
        runnerBaseURL: String? = nil
    ) {
        guard let normalizedURL = resolvedRunnerURL(explicit: runnerBaseURL) else { return }
        let projectID = WorkspaceProject.stableID(forRunnerBaseURL: normalizedURL)
        let existing = projectMatching(runnerURL: normalizedURL, preferredID: projectID)

        let project = WorkspaceProject(
            id: projectID,
            name: tree.name,
            remote: WorkspaceProject.resolveDisplayRemote(
                gitRemote: gitRemote,
                previousRemote: existing?.remote,
                fallbackRoot: remoteRoot
            ),
            defaultBranch: WorkspaceProject.resolveBranch(
                live: gitBranch,
                previous: existing?.defaultBranch
            ),
            root: tree,
            runnerBaseURL: normalizedURL,
            // Preserve Project Settings overrides across VFS refresh.
            customName: existing?.customName,
            apiToken: existing?.apiToken
        )

        let previousSelection = selectedFileID
        let previousPath = previousSelection.flatMap { id in
            if let node = existing?.root.find(id: id) { return node.path }
            return WorkspaceNode.pathFromVFSNodeID(id)
        }

        let wasOpen = selectedProjectID == existing?.id || selectedProjectID == projectID
        let shouldOpen = existing == nil || selectedProjectID == nil

        upsertProject(project, replacing: existing?.id)
        persistProjects()
        syncSourceControlBranch(
            projectID: projectID,
            branch: project.defaultBranch,
            migratingFrom: existing?.id
        )

        if shouldOpen {
            openProject(projectID)
        } else if wasOpen, selectedProjectID != projectID {
            selectedProjectID = projectID
        }

        guard selectedProjectID == projectID else { return }
        rebindSelection(previousSelection: previousSelection, previousPath: previousPath, in: project)
    }

    /// Patch branch/remote on an already-known project without replacing the tree.
    func applyVFSMetadata(
        gitRemote: String?,
        gitBranch: String?,
        runnerBaseURL: String?
    ) {
        guard let normalizedURL = resolvedRunnerURL(explicit: runnerBaseURL) else { return }
        let projectID = WorkspaceProject.stableID(forRunnerBaseURL: normalizedURL)
        guard let idx = projects.firstIndex(where: {
            $0.id == projectID || $0.normalizedRunnerURL == normalizedURL
        }) else {
            return
        }

        let current = projects[idx]
        let branch = WorkspaceProject.resolveBranch(live: gitBranch, previous: current.defaultBranch)
        let remote = WorkspaceProject.resolveDisplayRemote(
            gitRemote: gitRemote,
            previousRemote: current.remote,
            fallbackRoot: current.remote
        )
        guard branch != current.defaultBranch || remote != current.remote else { return }

        let updated = current.with(
            remote: remote,
            defaultBranch: branch,
            runnerBaseURL: current.runnerBaseURL ?? normalizedURL
        )
        projects[idx] = updated
        persistProjects()
        syncSourceControlBranch(projectID: updated.id, branch: branch, migratingFrom: nil)
    }

    /// Resolve relative VFS path for a node id in the active project.
    func vfsPath(forNodeID id: WorkspaceNode.ID) -> String? {
        selectedProject?.root.find(id: id)?.path
    }

    // MARK: - Private

    private func resolvedRunnerURL(explicit: String?) -> String? {
        let raw = explicit
            ?? selectedProject?.runnerBaseURL
            ?? projects.first(where: { $0.id == selectedProjectID })?.runnerBaseURL
        guard let raw, RunnerURL.isValid(raw) else { return nil }
        return RunnerURL.normalizeHTTP(raw)
    }

    private func projectMatching(runnerURL: String, preferredID: String) -> WorkspaceProject? {
        if let hit = projects.first(where: { $0.id == preferredID }) { return hit }
        if let hit = projects.first(where: { $0.normalizedRunnerURL == runnerURL }) { return hit }
        if let hit = projects.first(where: { $0.id == WorkspaceProject.vfsRemoteID }) { return hit }
        return nil
    }

    private func upsertProject(_ project: WorkspaceProject, replacing oldID: WorkspaceProject.ID?) {
        if let oldID, oldID != project.id, let idx = projects.firstIndex(where: { $0.id == oldID }) {
            projects[idx] = project
        } else if let idx = projects.firstIndex(where: { $0.id == project.id }) {
            projects[idx] = project
        } else {
            projects.insert(project, at: 0)
        }

        var seen = Set<String>()
        projects = projects.filter { item in
            guard let url = item.normalizedRunnerURL else { return true }
            if seen.contains(url) { return false }
            seen.insert(url)
            return true
        }
    }

    private func rebindSelection(
        previousSelection: WorkspaceNode.ID?,
        previousPath: String?,
        in project: WorkspaceProject
    ) {
        if let path = previousPath, let node = project.root.find(path: path) {
            selectedFileID = node.id
        } else if let previousSelection, project.root.find(id: previousSelection) != nil {
            selectedFileID = previousSelection
        } else if previousSelection != nil {
            selectedFileID = previousSelection
        }
    }

    private func syncSourceControlBranch(
        projectID: WorkspaceProject.ID,
        branch: String,
        migratingFrom oldID: WorkspaceProject.ID?
    ) {
        if let oldID, oldID != projectID, let sc = sourceControlByProject[oldID] {
            sourceControlByProject[projectID] = sc
            sourceControlByProject[oldID] = nil
        }
        guard var sc = sourceControlByProject[projectID] ?? sourceControl else { return }
        sc.applyBranchName(branch)
        sourceControlByProject[projectID] = sc
        if selectedProjectID == projectID {
            sourceControl = sc
        }
    }
}
