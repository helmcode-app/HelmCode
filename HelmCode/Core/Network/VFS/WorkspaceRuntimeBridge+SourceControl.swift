//
//  WorkspaceRuntimeBridge+SourceControl.swift
//  HelmCode
//
//  VFS git RPCs → WorkspaceSession Source Control state.
//

import Foundation

@MainActor
extension WorkspaceRuntimeBridge {
    /// Pull git status + refs into the Source Control sidebar.
    static func refreshSourceControl(
        from vfs: VFSNetworkEngine,
        to session: WorkspaceSession,
        forceLoading: Bool = false
    ) async {
        guard session.selectedProjectID != nil else { return }
        guard vfs.connectionState.isReady else { return }

        session.beginSourceControlLoading(force: forceLoading)
        do {
            async let statusTask = vfs.gitStatus()
            async let refsTask = vfs.gitRefs()
            let status = try await statusTask
            let refs = try await refsTask
            session.applyGitSnapshot(status: status, refs: refs)
        } catch {
            session.failSourceControl(sourceControlErrorMessage(error))
        }
    }

    /// Checkout a branch/tag, then refresh tree + SCM snapshot.
    static func checkoutSourceControlRef(
        _ ref: GitRef,
        from vfs: VFSNetworkEngine,
        to session: WorkspaceSession
    ) async {
        guard vfs.connectionState.isReady else {
            session.lastTreeError = "VFS is not connected."
            return
        }
        do {
            _ = try await vfs.gitCheckout(ref: ref.name, kind: ref.kind.vfsKind)
            session.clearSourceControlDiff()
            _ = try await vfs.initialize()
            await refreshSourceControl(from: vfs, to: session, forceLoading: true)
        } catch {
            session.lastTreeError = sourceControlErrorMessage(error)
        }
    }

    private static func sourceControlErrorMessage(_ error: Error) -> String {
        if let vfsError = error as? VFSError, case .rpc(let code, let message) = vfsError {
            if code == -32601 {
                return "Runner does not support git status yet."
            }
            return message
        }
        return error.localizedDescription
    }
}
