//
//  EditorCanvasView.swift
//  HelmCode
//
//  Code canvas: CodeMirror 6 host + status strip + line bookmarks.
//  VFS: load via vfs/read; save via vfs/write (autosave + ⌘S); didChange refresh when clean.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EditorCanvasView: View {
    let project: WorkspaceProject
    let file: WorkspaceNode
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @Environment(\.colorScheme) private var colorScheme

    @State private var buffer: String = ""
    /// Last successfully loaded or saved content (dirty = buffer != savedSnapshot).
    @State private var savedSnapshot: String = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var autosaveTask: Task<Void, Never>?
    /// Path currently bound to `buffer` (for flush-on-switch).
    @State private var boundPath: String = ""
    /// Line to reveal once after load / bookmark open (consumed from session).
    @State private var revealLine: Int?
    /// Bumps so the host re-runs goToLine for the same line if needed.
    @State private var revealGeneration: Int = 0

    private var language: CodeMirrorLanguage {
        CodeMirrorLanguage(languageHint: file.languageHint)
    }

    private var bookmarkLines: [Int] {
        session.bookmarkedLines(in: file.id)
    }

    private var usesVFS: Bool {
        project.isVFSRemote
    }

    private var isDirty: Bool {
        buffer != savedSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                CodeMirrorHostView(
                    text: buffer,
                    language: language,
                    isDark: colorScheme == .dark,
                    isEditable: true,
                    bookmarkLines: bookmarkLines,
                    revealLine: revealLine,
                    revealGeneration: revealGeneration,
                    preferSoftTextReplace: usesVFS,
                    onToggleBookmark: { line, text in
                        session.toggleLineBookmark(nodeID: file.id, line: line, lineText: text)
                    },
                    onTextChange: { text in
                        handleTextChange(text)
                    },
                    onSave: { text in
                        handleTextChange(text)
                        Task { await saveNow(content: text) }
                    }
                )
                .padding(.horizontal, LayoutMetrics.editorHorizontalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isLoading ? 0.45 : 1)

                if isLoading {
                    ProgressView()
                        .controlSize(.regular)
                }
            }

            Divider()
            statusBar
        }
        .background(Color(.systemBackground))
        .onChange(of: file.id) { _, _ in
            Task { await switchToCurrentFile() }
        }
        .onChange(of: project.id) { _, _ in
            Task { await switchToCurrentFile() }
        }
        .onChange(of: session.pendingEditorRevealLine) { _, _ in
            takePendingReveal()
        }
        .onChange(of: vfs.bufferRevision) { _, _ in
            applyRemoteCacheIfClean()
        }
        .onChange(of: vfs.lastChange) { _, change in
            guard usesVFS, let change else { return }
            // Match relative paths even if server prefixes differ slightly.
            guard pathsMatch(change.path, file.path) else { return }
            applyRemoteCacheIfClean()
            if !isDirty, vfs.cachedContent(for: file.path) == nil {
                Task { await reloadBuffer(markSaved: true) }
            }
        }
        .task(id: file.id) {
            await switchToCurrentFile()
            // Poll is a safety net only; primary path is didChange → bufferRevision.
            guard usesVFS else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled, usesVFS else { continue }
                await pollRemoteFile()
            }
        }
        .onDisappear {
            autosaveTask?.cancel()
            let path = boundPath
            let content = buffer
            let dirty = content != savedSnapshot
            guard usesVFS, dirty, !path.isEmpty else { return }
            Task { await persist(path: path, content: content) }
        }
    }

    // MARK: - Edit / save

    private func handleTextChange(_ text: String) {
        buffer = text
        saveError = nil
        guard usesVFS else { return }
        scheduleAutosave()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await saveNow(content: buffer)
        }
    }

    @MainActor
    private func saveNow(content: String) async {
        guard usesVFS else { return }
        guard content != savedSnapshot else { return }
        let path = file.path
        guard !path.isEmpty else { return }
        await persist(path: path, content: content)
    }

    @MainActor
    private func persist(path: String, content: String) async {
        guard usesVFS else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            _ = try await vfs.write(path: path, content: content)
            if path == file.path {
                savedSnapshot = content
                // Keep buffer in sync if save raced with further typing.
                if buffer == content {
                    saveError = nil
                }
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func switchToCurrentFile() async {
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
    /// Uses soft text replace in CM so the open tab stays put and top line is preserved.
    private func applyRemoteCacheIfClean() {
        guard usesVFS, !isDirty else { return }
        guard let cached = vfs.cachedContent(for: file.path), cached != buffer else { return }
        buffer = cached
        savedSnapshot = cached
        loadError = nil
    }

    private func pathsMatch(_ a: String, _ b: String) -> Bool {
        let na = a.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let nb = b.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return na == nb
    }

    /// Background re-fetch without the full loading overlay.
    @MainActor
    private func pollRemoteFile() async {
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

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(language.displayName, systemImage: "doc.plaintext")
            Text("UTF-8")
            Text("LF")
            Text("Wrap")
            if usesVFS {
                Text(vfs.connectionState.isReady ? "VFS" : "VFS…")
                    .foregroundStyle(vfs.connectionState.statusForeground)
                saveStatusLabel
            }
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(engine.phase.label)
                .foregroundStyle(engine.phase.isBusy ? Color.accentColor : .secondary)
            if let id = engine.activeTaskID {
                Text(id.prefix(8) + "…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var saveStatusLabel: some View {
        if isSaving {
            Text("Saving…")
                .foregroundStyle(Color.accentColor)
        } else if isDirty {
            Text("Modified")
                .foregroundStyle(Color.orange)
        } else if usesVFS, !boundPath.isEmpty {
            Text("Saved")
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func reloadBuffer(markSaved: Bool) async {
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

    private func takePendingReveal() {
        if let line = session.consumePendingRevealLine() {
            revealLine = line
            revealGeneration &+= 1
        }
    }
}
