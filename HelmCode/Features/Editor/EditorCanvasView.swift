//
//  EditorCanvasView.swift
//  HelmCode
//
//  Code canvas: CodeMirror 6 + status strip.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EditorCanvasView: View {
    let project: WorkspaceProject?
    let file: WorkspaceNode?
    @ObservedObject var engine: HelmCodeNetworkEngine
    @Environment(\.colorScheme) private var colorScheme

    @State private var buffer: String = ""

    private var language: CodeMirrorLanguage {
        CodeMirrorLanguage(languageHint: file?.languageHint)
    }

    var body: some View {
        VStack(spacing: 0) {
            CodeMirrorHostView(
                text: buffer,
                language: language,
                isDark: colorScheme == .dark,
                isEditable: true
            )
            .padding(.horizontal, LayoutMetrics.editorHorizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            statusBar
        }
        .background(Color(.systemBackground))
        .onChange(of: file?.id) { _, _ in reloadBuffer() }
        .onChange(of: project?.id) { _, _ in reloadBuffer() }
        .onAppear { reloadBuffer() }
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
        guard let file, !file.isDirectory, let project else {
            buffer = ""
            return
        }
        buffer = EditorSampleLibrary.content(for: file.path, project: project.name)
    }
}
