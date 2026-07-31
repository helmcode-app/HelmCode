//
//  BackendConnectionSync.swift
//  HelmCode
//
//  Keep HTTP task engine + VFS tunnel on the same base URL / token.
//

import Foundation

@MainActor
enum BackendConnectionSync {
    /// Copy HTTP engine credentials onto the VFS engine (does not start the tunnel).
    static func syncVFS(from engine: HelmCodeNetworkEngine, to vfs: VFSNetworkEngine) {
        vfs.baseURLString = engine.baseURLString
        vfs.apiToken = engine.apiToken
    }

    /// Apply a runner base URL (+ optional token) to both engines.
    static func apply(
        urlString: String,
        token: String? = nil,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine
    ) {
        let httpURL = RunnerURL.normalizeHTTP(urlString)
        engine.baseURLString = httpURL
        if let token {
            engine.apiToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        syncVFS(from: engine, to: vfs)
    }
}
