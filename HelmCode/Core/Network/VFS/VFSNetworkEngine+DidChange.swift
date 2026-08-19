//
//  VFSNetworkEngine+DidChange.swift
//  HelmCode
//
//  vfs/didChange → open buffers + coalesced tree refresh.
//  Bulk worktree rewrites arrive as `type: sync` (Terminal git switch).
//

import Foundation
import os.log

extension VFSNetworkEngine {

    /// Re-read files the user already opened. Does not pull the whole worktree.
    func reloadCachedBuffers() async {
        let paths = Set(fileBuffers.keys.map { VFSPath.normalize($0) })
        for path in paths where !path.isEmpty {
            await reloadCachedPath(path)
        }
    }

    /// Relist the worktree, then re-read already-open buffers (checkout / bulk sync).
    func refreshTreeAndOpenBuffers() async throws {
        treeRefreshTask?.cancel()
        _ = try await initialize(root: nil)
        await reloadCachedBuffers()
    }

    /// Publish assembled stream content into the buffer map (no network I/O).
    func cacheContent(_ content: String, for path: String) {
        writeCachedContent(content, for: path)
        bufferRevision &+= 1
    }

    func applyDidChange(_ change: VFSDidChangeParams) async {
        if VFSPath.isGitHead(change.path) {
            // Branch label / SCM come from gitStatus (`lastChange` already published).
            return
        }
        switch change.type {
        case .sync:
            await refreshTreeAndOpenBuffersSoft()
        case .write:
            guard hasCachedBuffer(for: change.path) else { return }
            await reloadCachedPath(change.path)
        case .create, .rename:
            let key = VFSPath.normalize(change.path)
            if hasCachedBuffer(for: change.path) || hotReloadPaths.contains(key) {
                hotReloadPaths.remove(key)
                await reloadCachedPath(change.path)
            }
            scheduleTreeRefresh()
        case .remove:
            if hasCachedBuffer(for: change.path) {
                hotReloadPaths.insert(VFSPath.normalize(change.path))
                await reloadCachedPath(change.path)
            }
            scheduleTreeRefresh()
        }
    }

    func hasCachedBuffer(for path: String) -> Bool {
        cachedContent(for: path) != nil
    }

    func reloadCachedPath(_ path: String) async {
        do {
            _ = try await readStreaming(path: path)
        } catch {
            dropCachedBuffer(path)
            log.error("selective reload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dropCachedBuffer(_ path: String) {
        removeCachedKeys(for: path)
        bufferRevision &+= 1
    }

    func scheduleTreeRefresh() {
        treeRefreshTask?.cancel()
        treeRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.treeRefreshDebounceNanoseconds ?? 200_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.refreshTreeAndOpenBuffersSoft()
        }
    }

    func refreshTreeAndOpenBuffersSoft() async {
        do {
            try await refreshTreeAndOpenBuffers()
        } catch {
            log.error("tree refresh after didChange failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeCachedContent(_ content: String, for path: String) {
        fileBuffers[path] = content
        let normalized = VFSPath.normalize(path)
        if normalized != path {
            fileBuffers[normalized] = content
        }
    }

    private func removeCachedKeys(for path: String) {
        fileBuffers.removeValue(forKey: path)
        let normalized = VFSPath.normalize(path)
        if normalized != path {
            fileBuffers.removeValue(forKey: normalized)
        }
    }
}
