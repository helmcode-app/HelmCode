//
//  EditorCanvasView.swift
//  HelmCode
//
//  Code canvas: CodeMirror 6 host + status strip + line bookmarks.
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
    @Environment(\.colorScheme) private var colorScheme

    @State private var buffer: String = ""
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

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()
            statusBar
        }
        .background(Color(.systemBackground))
        .onChange(of: file.id) { _, _ in
            reloadBuffer()
            takePendingReveal()
        }
        .onChange(of: project.id) { _, _ in
            reloadBuffer()
            takePendingReveal()
        }
        .onChange(of: session.pendingEditorRevealLine) { _, _ in
            takePendingReveal()
        }
        .onAppear {
            reloadBuffer()
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

    private func reloadBuffer() {
        guard !file.isDirectory else {
            buffer = ""
            return
        }
        buffer = EditorSampleLibrary.content(for: file.path, project: project.name)
    }

    private func takePendingReveal() {
        if let line = session.consumePendingRevealLine() {
            revealLine = line
            revealGeneration &+= 1
        }
    }
}
