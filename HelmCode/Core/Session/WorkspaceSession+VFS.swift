//
//  WorkspaceSession+VFS.swift
//  HelmCode
//
//  Apply remote VFS tree / metadata into the open-project session model.
//

import Foundation

extension WorkspaceSession {
    /// Install / refresh a runner-backed project from a nested VFS tree.
    /// Identity is runner URL + workspace id (one project per cloned repo).
    func applyVFSTree(
        _ tree: WorkspaceNode,
        remoteRoot: String,
        gitRemote: String? = nil,
        gitBranch: String? = nil,
        runnerBaseURL: String? = nil,
        workspaceId: String? = nil
    ) {
        guard let normalizedURL = resolvedRunnerURL(explicit: runnerBaseURL) else { return }
        let resolvedWorkspaceId = WorkspaceProject.normalizedWorkspaceId(workspaceId)
        let pending = pendingRunnerBinding.flatMap { binding -> (url: String, runnerId: String)? in
            RunnerURL.normalizeHTTP(binding.url) == normalizedURL ? binding : nil
        }
        let preferredID = WorkspaceProject.stableID(
            forRunnerBaseURL: normalizedURL,
            workspaceId: resolvedWorkspaceId
        )
        let byWorkspace = projects.first {
            $0.normalizedRunnerURL == normalizedURL &&
            $0.workspaceId == resolvedWorkspaceId
        }
        let byRunner = pending.flatMap { binding in
            projects.first {
                $0.runnerId == binding.runnerId && $0.workspaceId == resolvedWorkspaceId
            }
        }
        let urlMatch = projectMatching(runnerURL: normalizedURL, preferredID: preferredID)
        let existing = byWorkspace ?? byRunner ?? urlMatch
        let projectID = existing?.id ?? preferredID
        let runnerId = existing?.runnerId ?? pending?.runnerId

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
            runnerId: runnerId,
            workspaceId: resolvedWorkspaceId
        )

        let previousSelection = selectedFileID
        let previousPath = previousSelection.flatMap { id in
            if let node = existing?.root.find(id: id) { return node.path }
            return WorkspaceNode.pathFromVFSNodeID(id)
        }

        let wasOpen = selectedProjectID == existing?.id || selectedProjectID == projectID
        let shouldOpen = existing == nil || selectedProjectID == nil

        upsertProject(project, replacing: existing?.id)
        if pending?.runnerId == runnerId {
            pendingRunnerBinding = nil
        }
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
        runnerBaseURL: String?,
        workspaceId: String? = nil
    ) {
        guard let normalizedURL = resolvedRunnerURL(explicit: runnerBaseURL) else { return }
        let resolvedWorkspaceId = WorkspaceProject.normalizedWorkspaceId(workspaceId)
        let projectID = WorkspaceProject.stableID(
            forRunnerBaseURL: normalizedURL,
            workspaceId: resolvedWorkspaceId
        )
        guard let idx = projects.firstIndex(where: {
            $0.id == projectID ||
            ($0.normalizedRunnerURL == normalizedURL && $0.workspaceId == resolvedWorkspaceId)
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
        // Never fall back to "any project on this runner URL" — that collapses
        // multiple workspaces into the first cloned repo.
        _ = runnerURL
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

        // One project per (runner URL, workspaceId) — not per runner URL alone.
        var seen = Set<String>()
        projects = projects.filter { item in
            guard let url = item.normalizedRunnerURL else { return true }
            let key = "\(url)#\(item.workspaceId)"
            if seen.contains(key) { return false }
            seen.insert(key)
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
