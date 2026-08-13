//
//  VFSNetworkEngine+Git.swift
//  HelmCode
//
//  Typed git RPCs for the Source Control sidebar / center-column diff.
//

import Foundation

extension VFSNetworkEngine {
    /// Working-tree status (`vfs/gitStatus`).
    func gitStatus() async throws -> VFSGitStatusResult {
        try await call(method: "vfs/gitStatus", params: VFSEmptyParams())
    }

    /// Local / remote branches and tags (`vfs/gitRefs`).
    func gitRefs() async throws -> VFSGitRefsResult {
        try await call(method: "vfs/gitRefs", params: VFSEmptyParams())
    }

    /// Unified diff for one path (`vfs/gitDiff`).
    func gitDiff(path: String, staged: Bool = false) async throws -> VFSGitDiffResult {
        try await call(
            method: "vfs/gitDiff",
            params: VFSGitDiffParams(path: path, staged: staged)
        )
    }

    /// File contents at a revision (`vfs/gitShow`, default `HEAD`).
    func gitShow(path: String, revision: String = "HEAD") async throws -> VFSGitShowResult {
        try await call(
            method: "vfs/gitShow",
            params: VFSGitShowParams(path: path, revision: revision)
        )
    }

    /// Switch HEAD to a local/remote branch or tag (`vfs/gitCheckout`).
    func gitCheckout(ref: String, kind: VFSGitRefKind) async throws -> VFSGitCheckoutResult {
        try await call(
            method: "vfs/gitCheckout",
            params: VFSGitCheckoutParams(ref: ref, kind: kind)
        )
    }
}
