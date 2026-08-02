//
//  VFSStreamEngine.swift
//  HelmCode
//
//  Chunked `vfs/read_chunk` assembly for progressive editor open.
//  Wire models: VFSModels.swift · transport: VFSNetworkEngine.
//

import Combine
import Foundation
import os.log

/// Iterative `vfs/read_chunk` client. One stream per file open; cancelable via Task.
@MainActor
final class VFSStreamEngine: ObservableObject {

    @Published private(set) var phase: VFSStreamPhase = .idle
    @Published private(set) var progress: VFSStreamProgress?
    @Published private(set) var lastError: String?

    private let log = Logger(subsystem: "com.helmcode.HelmCode", category: "VFSStream")
    private var activeTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    /// Cancel any in-flight stream (e.g. user switched files).
    func cancel() {
        generation &+= 1
        activeTask?.cancel()
        activeTask = nil
        phase = .idle
        progress = nil
    }

    /**
     Stream a remote file via chunked JSON-RPC.

     - Parameters:
       - path: VFS relative path
       - expectedSize: tree `node.size` (0 still streams until is_eof)
       - vfs: connected `VFSNetworkEngine`
       - onChunk: called on MainActor after each chunk (`isFirst` for setDocument vs append)
       - onComplete: final assembled UTF-8 text
     */
    func streamFile(
        path: String,
        expectedSize: Int64,
        vfs: VFSNetworkEngine,
        chunkLimit: Int = VFSStreamDefaults.chunkLimit,
        onChunk: @escaping @MainActor (_ text: String, _ isFirst: Bool, _ progress: VFSStreamProgress) -> Void,
        onComplete: @escaping @MainActor (_ fullText: String, _ progress: VFSStreamProgress) -> Void
    ) {
        activeTask?.cancel()
        activeTask = nil
        generation &+= 1
        let gen = generation
        lastError = nil

        let large = expectedSize > VFSStreamDefaults.largeFileThreshold
        progress = VFSStreamProgress(
            path: path,
            loadedBytes: 0,
            totalBytes: max(0, expectedSize),
            isLargeFile: large,
            isComplete: false,
            isReadOnlyRecommended: large
        )
        phase = .streaming(path: path, loaded: 0, total: max(0, expectedSize))

        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let full = try await self.runStream(
                    path: path,
                    expectedSize: expectedSize,
                    vfs: vfs,
                    chunkLimit: chunkLimit,
                    generation: gen,
                    onChunk: onChunk
                )
                guard gen == self.generation, !Task.isCancelled else { return }
                let done = VFSStreamProgress(
                    path: path,
                    loadedBytes: Int64(full.utf8.count),
                    totalBytes: max(expectedSize, Int64(full.utf8.count)),
                    isLargeFile: large,
                    isComplete: true,
                    isReadOnlyRecommended: large
                )
                self.progress = done
                self.phase = .complete(path: path)
                onComplete(full, done)
            } catch is CancellationError {
                // ignored
            } catch {
                guard gen == self.generation else { return }
                self.lastError = error.localizedDescription
                self.phase = .failed(path: path, message: error.localizedDescription)
                self.log.error("stream failed \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func runStream(
        path: String,
        expectedSize: Int64,
        vfs: VFSNetworkEngine,
        chunkLimit: Int,
        generation gen: UInt64,
        onChunk: @MainActor (String, Bool, VFSStreamProgress) -> Void
    ) async throws -> String {
        var offset: Int64 = 0
        var assembled = String()
        if expectedSize > 0, expectedSize < Int64(Int.max) {
            assembled.reserveCapacity(Int(min(expectedSize, 16 * 1024 * 1024)))
        }

        var isFirst = true
        var fileSize = expectedSize
        let large = expectedSize > VFSStreamDefaults.largeFileThreshold

        while !Task.isCancelled {
            guard gen == generation else { throw CancellationError() }

            let chunk = try await vfs.readChunk(
                path: path,
                offset: offset,
                limit: chunkLimit
            )
            guard gen == generation, !Task.isCancelled else { throw CancellationError() }

            if chunk.fileSize > 0 {
                fileSize = chunk.fileSize
            }
            if !chunk.content.isEmpty {
                assembled.append(chunk.content)
            }

            let loaded = offset + Int64(chunk.bytesRead)
            let prog = VFSStreamProgress(
                path: path,
                loadedBytes: loaded,
                totalBytes: max(fileSize, loaded),
                isLargeFile: large || fileSize > VFSStreamDefaults.largeFileThreshold,
                isComplete: chunk.isEOF,
                isReadOnlyRecommended: large || fileSize > VFSStreamDefaults.largeFileThreshold
            )
            progress = prog
            phase = .streaming(path: path, loaded: prog.loadedBytes, total: prog.totalBytes)
            onChunk(chunk.content, isFirst, prog)
            isFirst = false

            if chunk.isEOF {
                return assembled
            }

            let step = chunk.bytesRead > 0 ? Int64(chunk.bytesRead) : Int64(chunkLimit)
            offset += step
            if step == 0 {
                return assembled
            }
        }
        throw CancellationError()
    }
}

// MARK: - VFSNetworkEngine chunk API

extension VFSNetworkEngine {
    /// Single bounded `vfs/read_chunk` RPC (does not touch fileBuffers).
    func readChunk(
        path: String,
        offset: Int64,
        limit: Int = VFSStreamDefaults.chunkLimit
    ) async throws -> VFSReadChunkResult {
        try await call(
            method: "vfs/read_chunk",
            params: VFSReadChunkParams(path: path, offset: offset, limit: limit)
        )
    }

    /**
     Stream-assemble a file via read_chunk into `fileBuffers` (and return full text).
     Prefer `VFSStreamEngine` when the editor needs progressive CM injection.
     */
    @discardableResult
    func readStreaming(
        path: String,
        expectedSize: Int64 = 0,
        chunkLimit: Int = VFSStreamDefaults.chunkLimit
    ) async throws -> String {
        var offset: Int64 = 0
        var assembled = ""
        if expectedSize > 0, expectedSize < Int64(Int.max) {
            assembled.reserveCapacity(Int(min(expectedSize, 8 * 1024 * 1024)))
        }
        while true {
            let chunk = try await readChunk(path: path, offset: offset, limit: chunkLimit)
            if !chunk.content.isEmpty {
                assembled.append(chunk.content)
            }
            if chunk.isEOF { break }
            let step = chunk.bytesRead > 0 ? Int64(chunk.bytesRead) : Int64(chunkLimit)
            if step == 0 { break }
            offset += step
        }
        cacheContent(assembled, for: path)
        return assembled
    }
}
