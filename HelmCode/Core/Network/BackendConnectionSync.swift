//
//  BackendConnectionSync.swift
//  HelmCode
//
//  Keep HTTP task engine + VFS tunnel + Agent WebSocket on the same base URL / token.
//

import Foundation

@MainActor
enum BackendConnectionSync {
    /// Copy HTTP engine credentials onto the VFS engine (does not start the tunnel).
    static func syncVFS(from engine: HelmCodeNetworkEngine, to vfs: VFSNetworkEngine) {
        vfs.baseURLString = engine.baseURLString
        vfs.apiToken = engine.apiToken
    }

    /// Copy HTTP engine credentials onto the Agent WebSocket engine (no auto-start).
    static func syncAgent(from engine: HelmCodeNetworkEngine, to agent: AgentNetworkEngine) {
        agent.syncCredentials(from: engine)
    }

    /// Keep VFS + Agent credentials aligned with the HTTP engine.
    static func syncAll(
        from engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine,
        agent: AgentNetworkEngine
    ) {
        syncVFS(from: engine, to: vfs)
        syncAgent(from: engine, to: agent)
    }

    /// Apply a runner base URL (+ optional token) to HTTP + VFS (+ optional agent).
    static func apply(
        urlString: String,
        token: String? = nil,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine,
        agent: AgentNetworkEngine? = nil
    ) {
        let httpURL = RunnerURL.normalizeHTTP(urlString)
        engine.baseURLString = httpURL
        if let token {
            engine.apiToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        syncVFS(from: engine, to: vfs)
        if let agent {
            syncAgent(from: engine, to: agent)
        }
    }
}
