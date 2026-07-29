//
//  EditorCanvasView.swift
//  HelmCode
//
//  Main code editor — CodeMirror 6 hosted in WKWebView (soft wrap + highlighting).
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

    @State private var buffer: String = EditorCanvasView.placeholder

    private var language: CodeMirrorLanguage {
        CodeMirrorLanguage(languageHint: file?.languageHint)
    }

    var body: some View {
        VStack(spacing: 0) {
            CodeMirrorHostView(
                text: buffer,
                language: language,
                isDark: colorScheme == .dark,
                isEditable: true,
                lineWrapping: true
            )
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
            Text("CodeMirror 6")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
                .fixedSize(horizontal: true, vertical: false)
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
            buffer = Self.placeholder
            return
        }
        buffer = EditorSampleLibrary.content(for: file.path, project: project.name)
    }

    private static let placeholder = """
    // HelmCode · CodeMirror 6
    //
    // Select a file from the workspace sidebar.
    // Soft-wrap and language highlighting are provided by CodeMirror 6.

    """
}
