//
//  EditorCanvasView+Persistence.swift
//  HelmCode
//
//  Load / save / poll / remote-cache for the center-column editor.
//

import Foundation

extension EditorCanvasView {
    // MARK: - Edit / save

    func handleTextChange(_ text: String) {
        buffer = text
        saveError = nil
        guard usesVFS else { return }
        scheduleAutosave()
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await saveNow(content: buffer)
        }
    }

    @MainActor
    func saveNow(content: String) async {
        guard usesVFS else { return }
        guard content != savedSnapshot else { return }
        let path = file.path
        guard !path.isEmpty else { return }
        await persist(path: path, content: content)
    }

    @MainActor
    func persist(path: String, content: String) async {
        guard usesVFS else { return }
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
        // Flush previous dirty buffer before rebinding.
        if usesVFS, !boundPath.isEmpty, boundPath != file.path, buffer != savedSnapshot {
            await persist(path: boundPath, content: buffer)
        }
        boundPath = file.path
        await reloadBuffer(markSaved: true)
        takePendingReveal()
    }

    /// Apply remote cache only when local buffer is clean (avoid clobbering edits).
    func applyRemoteCacheIfClean() {
        guard usesVFS, !isDirty else { return }
        guard let cached = vfs.cachedContent(for: file.path), cached != buffer else { return }
        buffer = cached
        savedSnapshot = cached
        loadError = nil
    }

    /// Background re-fetch without the full loading overlay.
    @MainActor
    func pollRemoteFile() async {
        guard usesVFS, !file.isDirectory, !isDirty, !isSaving else { return }
        do {
            let result = try await vfs.read(path: file.path)
            if result.content != buffer {
                buffer = result.content
                savedSnapshot = result.content
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
            return
        }

        if usesVFS {
            if let cached = vfs.cachedContent(for: file.path) {
                buffer = cached
                if markSaved { savedSnapshot = cached }
                loadError = nil
            }
            isLoading = buffer.isEmpty
            do {
                let result = try await vfs.read(path: file.path)
                buffer = result.content
                if markSaved { savedSnapshot = result.content }
                loadError = nil
            } catch {
                if buffer.isEmpty {
                    loadError = error.localizedDescription
                }
            }
            isLoading = false
            return
        }

        buffer = EditorSampleLibrary.content(for: file.path, project: project.name)
        if markSaved { savedSnapshot = buffer }
        loadError = nil
        isSaving = false
        isLoading = false
    }

    func takePendingReveal() {
        if let line = session.consumePendingRevealLine() {
            revealLine = line
            revealGeneration &+= 1
        }
    }
}
