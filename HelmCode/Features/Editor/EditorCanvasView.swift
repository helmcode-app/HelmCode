//
//  EditorCanvasView.swift
//  HelmCode
//
//  Code canvas: CodeMirror 6 host + status strip + line bookmarks.
//  Remote files load via VFS `vfs/read`; `vfs/didChange` refreshes the buffer.
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
    @State private var isLoading = false
    @State private var loadError: String?
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
        project.id == WorkspaceSession.vfsProjectID
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
                    onToggleBookmark: { line, text in
                        session.toggleLineBookmark(nodeID: file.id, line: line, lineText: text)
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
            Task { await reloadBuffer() }
            takePendingReveal()
        }
        .onChange(of: project.id) { _, _ in
            Task { await reloadBuffer() }
            takePendingReveal()
        }
        .onChange(of: session.pendingEditorRevealLine) { _, _ in
            takePendingReveal()
        }
        .onChange(of: vfs.bufferRevision) { _, _ in
            guard usesVFS else { return }
            if let cached = vfs.cachedContent(for: file.path), cached != buffer {
                buffer = cached
                loadError = nil
            }
        }
        .onChange(of: vfs.lastChange) { _, change in
            guard usesVFS, let change, change.path == file.path else { return }
            // Selective reload already runs in the engine; bind any fresh cache.
            if let cached = vfs.cachedContent(for: file.path) {
                buffer = cached
            } else {
                Task { await reloadBuffer() }
            }
        }
        .task(id: file.id) {
            await reloadBuffer()
            takePendingReveal()
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
                    .foregroundStyle(vfs.connectionState.isReady ? Color.secondary : Color.orange)
            }
            if let loadError {
                Text(loadError)
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

    @MainActor
    private func reloadBuffer() async {
        guard !file.isDirectory else {
            buffer = ""
            return
        }

        if usesVFS {
            if let cached = vfs.cachedContent(for: file.path) {
                buffer = cached
                loadError = nil
            }
            isLoading = buffer.isEmpty
            do {
                let result = try await vfs.read(path: file.path)
                buffer = result.content
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
        loadError = nil
        isLoading = false
    }

    private func takePendingReveal() {
        if let line = session.consumePendingRevealLine() {
            revealLine = line
            revealGeneration &+= 1
        }
    }
}
