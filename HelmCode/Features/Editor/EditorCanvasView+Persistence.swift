//
//  EditorCanvasView+Persistence.swift
//  HelmCode
//
//  Load / save / poll / remote-cache for the center-column editor.
//  Large VFS files use chunked vfs/read_chunk via VFSStreamEngine.
//

import Foundation

extension EditorCanvasView {
    // MARK: - Edit / save

    func handleTextChange(_ text: String) {
        // Streaming uses host buffer; CM must not overwrite it with "" echoes.
        guard !streamMode, !isReadOnlyStream else { return }
        buffer = text
        saveError = nil
        guard usesVFS else { return }
        scheduleAutosave()
    }

    func scheduleAutosave() {
        guard !isReadOnlyStream else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await saveNow(content: buffer)
        }
    }

    @MainActor
    func saveNow(content: String) async {
        guard usesVFS, !isReadOnlyStream else { return }
        guard content != savedSnapshot else { return }
        let path = file.path
        guard !path.isEmpty else { return }
        await persist(path: path, content: content)
    }

    @MainActor
    func persist(path: String, content: String) async {
        guard usesVFS, !isReadOnlyStream else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await vfs.write(path: path, content: content)
            if path == file.path {
                savedSnapshot = content
                if buffer == content {
                    saveError = nil
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    func switchToCurrentFile() async {
        autosaveTask?.cancel()
        streamEngine.cancel()
        if usesVFS, !isReadOnlyStream, !boundPath.isEmpty, boundPath != file.path, buffer != savedSnapshot {
            await persist(path: boundPath, content: buffer)
        }
        boundPath = file.path
        isReadOnlyStream = file.size > VFSStreamDefaults.largeFileThreshold
        cursorLine = 1
        cursorColumn = 1
        await reloadBuffer(markSaved: true)
        takePendingReveal()
    }

    func applyRemoteCacheIfClean() {
        guard usesVFS, !isDirty, !isReadOnlyStream else { return }
        guard let cached = vfs.cachedContent(for: file.path), cached != buffer else { return }
        buffer = cached
        savedSnapshot = cached
        loadError = nil
    }

    @MainActor
    func pollRemoteFile() async {
        guard usesVFS, !file.isDirectory, !isDirty, !isSaving, !isReadOnlyStream else { return }
        do {
            let text = try await vfs.readStreaming(path: file.path, expectedSize: file.size)
            if text != buffer {
                buffer = text
                savedSnapshot = text
                loadError = nil
            }
        } catch {
            if buffer.isEmpty {
                loadError = error.localizedDescription
            }
        }
    }

    @MainActor
    func reloadBuffer(markSaved: Bool) async {
        guard !file.isDirectory else {
            buffer = ""
            savedSnapshot = ""
            streamMode = false
            isLoading = false
            streamProgress = nil
            return
        }

        if usesVFS {
            await streamReloadFromVFS(markSaved: markSaved)
            return
        }

        buffer = EditorSampleLibrary.content(for: file.path, project: project.name)
        if markSaved { savedSnapshot = buffer }
        loadError = nil
        isSaving = false
        isLoading = false
        streamMode = false
        streamProgress = nil
    }

    /// Chunked open: vfs/read_chunk loop + progressive CodeMirror injection.
    @MainActor
    private func streamReloadFromVFS(markSaved: Bool) async {
        loadError = nil
        streamEngine.cancel()
        streamProgress = nil

        // Stream always rebuilds from server; optional cache is paint-only until first chunk.
        let warm = vfs.cachedContent(for: file.path) ?? ""
        buffer = warm
        if markSaved { savedSnapshot = warm }

        isLoading = true
        streamMode = true
        isReadOnlyStream = file.size > VFSStreamDefaults.largeFileThreshold
        streamBeginGeneration &+= 1

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var finished = false
            var startedFresh = false
            let done: () -> Void = {
                guard !finished else { return }
                finished = true
                cont.resume()
            }

            streamEngine.streamFile(
                path: file.path,
                expectedSize: file.size,
                vfs: vfs,
                onChunk: { chunk, isFirst, prog in
                    if isFirst {
                        // Replace any warm cache; first chunk owns the buffer.
                        buffer = chunk
                        startedFresh = true
                    } else if !chunk.isEmpty {
                        buffer.append(chunk)
                    }
                    if !chunk.isEmpty || isFirst {
                        streamChunkText = chunk
                        streamChunkGeneration &+= 1
                    }
                    streamProgress = prog
                    isReadOnlyStream = prog.isReadOnlyRecommended
                    if prog.loadedBytes > 0 || startedFresh {
                        isLoading = false
                    }
                },
                onComplete: { full, prog in
                    // Set buffer before end generation so CM endStreamDocument sees full text.
                    buffer = full
                    if markSaved { savedSnapshot = full }
                    streamProgress = prog
                    isReadOnlyStream = prog.isReadOnlyRecommended
                    streamEndGeneration &+= 1
                    // Keep streamMode true until after end is applied in the next frame,
                    // so documentChange echoes from setDocument("") still ignore.
                    isLoading = false
                    loadError = nil
                    vfs.cacheContent(full, for: file.path)
                    Task { @MainActor in
                        // Allow WK evaluate of final setDocument to land, then leave stream mode.
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        streamMode = false
                        done()
                    }
                }
            )

            Task { @MainActor in
                while !finished {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    if case .failed(_, let msg) = streamEngine.phase {
                        loadError = msg
                        isLoading = false
                        streamMode = false
                        done()
                        return
                    }
                    if case .complete = streamEngine.phase {
                        done()
                        return
                    }
                }
            }
        }

        isLoading = false
    }

    func takePendingReveal() {
        if let line = session.consumePendingRevealLine() {
            revealLine = line
            revealGeneration &+= 1
        }
    }
}
