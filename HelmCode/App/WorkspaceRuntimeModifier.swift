//
//  WorkspaceRuntimeModifier.swift
//  HelmCode
//
//  Binds VFS / HTTP / Agent engines to WorkspaceSession (used by RootView).
//

import SwiftUI

/// Keeps session projects in sync with VFS and activates the selected runner.
struct WorkspaceRuntimeModifier: ViewModifier {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor

    func body(content: Content) -> some View {
        content
            .task {
                // Do not auto-start VFS/Agent until a project is opened.
                refreshRunnerStatus()
            }
            .onChange(of: session.selectedProjectID) { _, _ in
                Task { await activateSelectedProject() }
            }
            .onChange(of: engine.baseURLString) { _, _ in
                syncEnginesAndStatus()
            }
            .onChange(of: engine.apiToken) { _, _ in
                syncEnginesAndStatus()
            }
            .onChange(of: vfs.tree) { _, _ in
                WorkspaceRuntimeBridge.applyTree(from: vfs, engine: engine, to: session)
                refreshRunnerStatus()
            }
            .onChange(of: vfs.workspaceBranch) { _, _ in
                WorkspaceRuntimeBridge.applyMetadata(from: vfs, engine: engine, to: session)
            }
            .onChange(of: vfs.workspaceRemote) { _, _ in
                WorkspaceRuntimeBridge.applyMetadata(from: vfs, engine: engine, to: session)
            }
    }

    private func syncEnginesAndStatus() {
        BackendConnectionSync.syncAll(from: engine, vfs: vfs, agent: agent)
        refreshRunnerStatus()
    }

    private func refreshRunnerStatus() {
        runnerStatus.refresh(projects: session.projects, engine: engine)
    }

    private func activateSelectedProject() async {
        await WorkspaceRuntimeBridge.activateSelectedProject(
            session: session,
            engine: engine,
            vfs: vfs,
            agent: agent
        )
        refreshRunnerStatus()
    }
}
