//
//  WorkspaceRuntimeBridge.swift
//  HelmCode
//
//  Glue between VFS/HTTP/Agent engines and WorkspaceSession (used by RootView / Open Project).
//  Backend URL is project-scoped (`WorkspaceProject.runnerBaseURL`) — not a free-floating agent setting.
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
            runnerBaseURL: engine.baseURLString,
            workspaceId: vfs.workspaceId
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
            runnerBaseURL: engine.baseURLString,
            workspaceId: vfs.workspaceId
        )
    }

    /**
     Point HTTP + VFS + Agent at the selected project’s runner.

     - No project open → tear down VFS/Agent tunnels (Agent Command stays unavailable).
     - Project open → bind credentials from the project URL + shared token, then start tunnels.
     */
    static func activateSelectedProject(
        session: WorkspaceSession,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine,
        agent: AgentNetworkEngine
    ) async {
        guard let project = session.selectedProject,
              let url = project.normalizedRunnerURL else {
            detachWorkspaceEngines(vfs: vfs, agent: agent)
            return
        }

        let current = RunnerURL.normalizeHTTP(engine.baseURLString).lowercased()
        let target = url.lowercased()

        let token = project.deviceToken ?? ""
        if engine.apiToken != token {
            engine.apiToken = token
        }

        let workspaceId = project.workspaceId
        let workspaceChanged = agent.workspaceId != workspaceId
        // Drop previous project's chats immediately so the right rail cannot lag.
        if workspaceChanged {
            agent.clearChatSurface()
        }
        agent.workspaceId = workspaceId
        guard !Task.isCancelled else { return }

        if current != target {
            BackendConnectionSync.apply(
                urlString: url,
                token: token.isEmpty ? nil : token,
                engine: engine,
                vfs: vfs,
                agent: agent
            )
            await engine.checkBackendHealth()
            guard !Task.isCancelled else { return }
            vfs.workspaceId = workspaceId
            vfs.start()
            agent.bindToProjectRunner(from: engine)
            return
        }

        BackendConnectionSync.syncVFS(from: engine, to: vfs)
        BackendConnectionSync.syncAgent(from: engine, to: agent)
        let vfsWorkspaceChanged = vfs.workspaceId != workspaceId
        vfs.workspaceId = workspaceId

        if vfsWorkspaceChanged || !vfs.connectionState.isReady {
            await engine.checkBackendHealth()
            guard !Task.isCancelled else { return }
            vfs.start()
        }
        agent.bindToProjectRunner(from: engine)
        // Same runner stays connected — connect() will not re-run, so reload chats here.
        if workspaceChanged {
            await agent.reloadChatsForCurrentWorkspace()
        }
    }

    /// Close project / welcome: stop remote tunnels; keep HTTP engine idle for Settings probes.
    static func detachWorkspaceEngines(
        vfs: VFSNetworkEngine,
        agent: AgentNetworkEngine
    ) {
        agent.detachFromProject()
        vfs.stop()
    }

    // Source Control: WorkspaceRuntimeBridge+SourceControl.swift
}
