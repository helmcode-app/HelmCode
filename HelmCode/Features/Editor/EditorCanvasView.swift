//
//  EditorCanvasView.swift
//  HelmCode
//
//  Code canvas: CodeMirror 6 host + status strip + line bookmarks.
//  VFS: load via vfs/read_chunk stream; save via vfs/write (autosave + ⌘S).
//  Persistence helpers live in `EditorCanvasView+Persistence.swift`.
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

    @State var buffer: String = ""
    /// Last successfully loaded or saved content (dirty = buffer != savedSnapshot).
    @State var savedSnapshot: String = ""
    @State var isLoading = false
    @State var isSaving = false
    @State var loadError: String?
    @State var saveError: String?
    @State var autosaveTask: Task<Void, Never>?
    /// Path currently bound to `buffer` (for flush-on-switch).
    @State var boundPath: String = ""
    /// Line to reveal once after load / bookmark open (consumed from session).
    @State var revealLine: Int?
    /// Bumps so the host re-runs goToLine for the same line if needed.
    @State var revealGeneration: Int = 0

    // MARK: - Chunked stream
    @StateObject var streamEngine = VFSStreamEngine()
    @State var streamMode = false
    @State var streamBeginGeneration: UInt64 = 0
    @State var streamChunkGeneration: UInt64 = 0
    @State var streamChunkText = ""
    @State var streamEndGeneration: UInt64 = 0
    @State var streamProgress: VFSStreamProgress?
    @State var isReadOnlyStream = false

    var language: CodeMirrorLanguage {
        CodeMirrorLanguage(languageHint: file.languageHint)
    }

    var bookmarkLines: [Int] {
        session.bookmarkedLines(in: file.id)
    }

    var usesVFS: Bool {
        project.isVFSRemote
    }

    var isDirty: Bool {
        buffer != savedSnapshot
    }

    var body: some View {
        VStack(spacing: 0) {
            if isReadOnlyStream {
                largeFileBanner
            }
            ZStack {
                CodeMirrorHostView(
                    text: buffer,
                    language: language,
                    isDark: colorScheme == .dark,
                    isEditable: !isReadOnlyStream,
                    bookmarkLines: bookmarkLines,
                    revealLine: revealLine,
                    revealGeneration: revealGeneration,
                    preferSoftTextReplace: usesVFS && !streamMode,
                    streamMode: streamMode,
                    streamBeginGeneration: streamBeginGeneration,
                    streamChunkGeneration: streamChunkGeneration,
                    streamChunkText: streamChunkText,
                    streamEndGeneration: streamEndGeneration,
                    onToggleBookmark: { line, text in
                        session.toggleLineBookmark(nodeID: file.id, line: line, lineText: text)
                    },
                    onTextChange: { text in
                        // Never let CM empty-doc echoes wipe the stream buffer.
                        guard !streamMode else { return }
                        handleTextChange(text)
                    },
                    onSave: { text in
                        guard !streamMode, !isReadOnlyStream else { return }
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
        // Single load path: `.task(id:)` restarts on file change (avoid also onChange → double load).
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
        .onChange(of: session.pendingEditorRevealLine) { _, _ in
            takePendingReveal()
        }
        .onChange(of: vfs.bufferRevision) { _, _ in
            applyRemoteCacheIfClean()
        }
        .onChange(of: vfs.lastChange) { _, change in
            guard usesVFS, let change else { return }
            guard VFSPath.matches(change.path, file.path) else { return }
            applyRemoteCacheIfClean()
            if !isDirty, vfs.cachedContent(for: file.path) == nil {
                Task { await reloadBuffer(markSaved: true) }
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

    // MARK: - Status

    private var largeFileBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield")
            Text("Large file detected. Streaming in secure Read-Only mode.")
                .font(.footnote.weight(.medium))
            Spacer(minLength: 0)
            if let streamProgress, streamProgress.totalBytes > 0, !streamProgress.isComplete {
                Text("\(Int(streamProgress.fraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.18))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(language.displayName, systemImage: "doc.plaintext")
            Text("UTF-8")
            Text("LF")
            Text(isReadOnlyStream ? "Read-only" : "Wrap")
            if usesVFS {
                Text(vfs.connectionState.isReady ? "VFS" : "VFS…")
                    .foregroundStyle(vfs.connectionState.statusForeground)
                if !isReadOnlyStream {
                    saveStatusLabel
                }
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
            Text(engine.connectionState.shortTitle)
                .foregroundStyle(engine.connectionState.isOnline ? Color.secondary : Color.orange)
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
}
