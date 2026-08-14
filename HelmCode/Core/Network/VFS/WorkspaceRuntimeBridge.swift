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

        // Prefer this project's token, then last Open Project / Project Settings value.
        let projectToken = project.apiToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remembered = RunnerConnectionPrefs.apiToken()
        let token = !projectToken.isEmpty ? projectToken : remembered
        if engine.apiToken != token {
            engine.apiToken = token
        }

        if current != target {
            BackendConnectionSync.apply(
                urlString: url,
                token: token.isEmpty ? nil : token,
                engine: engine,
                vfs: vfs,
                agent: agent
            )
            await engine.checkBackendHealth()
            vfs.workspaceId = agent.workspaceId
            vfs.start()
            agent.bindToProjectRunner(from: engine)
            return
        }

        BackendConnectionSync.syncVFS(from: engine, to: vfs)
        BackendConnectionSync.syncAgent(from: engine, to: agent)
        vfs.workspaceId = agent.workspaceId

        if !vfs.connectionState.isReady {
            await engine.checkBackendHealth()
            vfs.start()
        }
        agent.bindToProjectRunner(from: engine)
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
