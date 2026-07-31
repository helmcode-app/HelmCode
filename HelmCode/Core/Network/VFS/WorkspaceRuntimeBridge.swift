//
//  WorkspaceRuntimeBridge.swift
//  HelmCode
//
//  Glue between VFS/HTTP engines and WorkspaceSession (used by RootView / Open Project).
//

import Foundation

@MainActor
enum WorkspaceRuntimeBridge {
    /// Push the current VFS tree + identity into the session catalog.
    static func applyTree(
        from vfs: VFSNetworkEngine,
        engine: HelmCodeNetworkEngine,
        to session: WorkspaceSession
    ) {
        guard let tree = vfs.tree, let root = vfs.workspaceRoot else { return }
        session.applyVFSTree(
            tree,
            remoteRoot: root,
            gitRemote: vfs.workspaceRemote,
            gitBranch: vfs.workspaceBranch,
            runnerBaseURL: engine.baseURLString
        )
    }

    /// Push branch/remote labels without replacing the file tree.
    static func applyMetadata(
        from vfs: VFSNetworkEngine,
        engine: HelmCodeNetworkEngine,
        to session: WorkspaceSession
    ) {
        guard vfs.workspaceBranch != nil || vfs.workspaceRemote != nil else { return }
        session.applyVFSMetadata(
            gitRemote: vfs.workspaceRemote,
            gitBranch: vfs.workspaceBranch,
            runnerBaseURL: engine.baseURLString
        )
    }

    /// Point HTTP + VFS at the selected project’s runner (no-op when none open).
    static func activateSelectedProject(
        session: WorkspaceSession,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine
    ) async {
        guard let project = session.selectedProject,
              let url = project.normalizedRunnerURL else {
            return
        }

        let current = RunnerURL.normalizeHTTP(engine.baseURLString).lowercased()
        let target = url.lowercased()

        if current != target {
            BackendConnectionSync.apply(urlString: url, engine: engine, vfs: vfs)
            await engine.checkBackendHealth()
            vfs.start()
            return
        }

        BackendConnectionSync.syncVFS(from: engine, to: vfs)
        if !vfs.connectionState.isReady {
            await engine.checkBackendHealth()
            vfs.start()
        }
    }
}
