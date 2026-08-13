//
//  WorkspaceSession+SourceControl.swift
//  HelmCode
//
//  Apply runner git snapshots into Source Control sidebar state.
//

import Foundation

@MainActor
extension WorkspaceSession {
    /// Mark SCM as loading when first opening / hard refresh.
    func beginSourceControlLoading(force: Bool = false) {
        updateSourceControl { state in
            if force || state.phase != .ready {
                state.phase = .loading
            }
            state.errorMessage = nil
        }
    }

    func failSourceControl(_ message: String) {
        updateSourceControl { state in
            state.phase = .error
            state.errorMessage = message
        }
    }

    func applyGitSnapshot(
        status: VFSGitStatusResult,
        refs: VFSGitRefsResult
    ) {
        let project = selectedProject
        updateSourceControl { state in
            state.apply(status: status, refs: refs, project: project)
        }
        // Keep project branch label in sync with live status when present.
        if let branch = status.branch?.trimmingCharacters(in: .whitespacesAndNewlines),
           !branch.isEmpty,
           let id = selectedProjectID,
           let idx = projects.firstIndex(where: { $0.id == id }),
           projects[idx].defaultBranch != branch {
            projects[idx] = projects[idx].with(defaultBranch: branch)
            persistProjects()
        }
    }

    // MARK: - Private

    private func updateSourceControl(_ body: (inout SourceControlState) -> Void) {
        guard let projectID = selectedProjectID else { return }
        var state = sourceControl
            ?? sourceControlByProject[projectID]
            ?? .empty(phase: .loading, branch: selectedProject?.displayBranch ?? "—")
        body(&state)
        sourceControl = state
        sourceControlByProject[projectID] = state
    }
}
