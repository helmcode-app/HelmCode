//
//  VFSConnect.swift
//  HelmCode
//
//  Open Project / Settings: apply runner URL and wait for VFS initialize.
//

import Foundation

enum VFSConnectError: LocalizedError {
    case invalidURL
    case healthFailed(String)
    case vfsFailed(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a valid runner URL (http:// or https://)."
        case .healthFailed(let message):
            return message
        case .vfsFailed(let message):
            return message
        case .timedOut:
            return "Could not reach VFS on this runner."
        }
    }
}

/// Outcome of connecting Open Project → self-hosted runner.
enum VFSConnectOutcome: Equatable {
    /// Tree applied into session; sheet may dismiss.
    case opened
    /// HTTP healthy; VFS still settling — dismiss and let RootView apply tree.
    case healthOnly
}

@MainActor
enum VFSConnect {
    /// Normalize URL, sync engines, health-check, start VFS, optionally apply tree.
    static func openSelfHosted(
        urlString: String,
        engine: HelmCodeNetworkEngine,
        vfs: VFSNetworkEngine,
        session: WorkspaceSession,
        waitAttempts: Int = 40,
        waitNanos: UInt64 = 100_000_000
    ) async throws -> VFSConnectOutcome {
        guard RunnerURL.isValid(urlString) else { throw VFSConnectError.invalidURL }

        BackendConnectionSync.apply(urlString: urlString, engine: engine, vfs: vfs)

        await engine.checkBackendHealth()
        if case .offline(let message) = engine.connectionState {
            throw VFSConnectError.healthFailed(message)
        }

        vfs.start()

        for _ in 0..<waitAttempts {
            if vfs.connectionState.isReady, let tree = vfs.tree, let root = vfs.workspaceRoot {
                session.applyVFSTree(
                    tree,
                    remoteRoot: root,
                    gitRemote: vfs.workspaceRemote,
                    runnerBaseURL: engine.baseURLString
                )
                return .opened
            }
            if case .failed(let message) = vfs.connectionState {
                throw VFSConnectError.vfsFailed(message)
            }
            try? await Task.sleep(nanoseconds: waitNanos)
        }

        if engine.connectionState.isOnline {
            return .healthOnly
        }

        throw VFSConnectError.vfsFailed(vfs.lastError ?? VFSConnectError.timedOut.localizedDescription)
    }
}
