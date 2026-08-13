//
//  SourceControlDiffView.swift
//  HelmCode
//
//  Features/SourceControl — center-column CodeMirror unified-merge Diff.
//

import SwiftUI

struct SourceControlDiffView: View {
    let project: WorkspaceProject
    let request: SourceControlDiffRequest
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var vfs: VFSNetworkEngine
    @Environment(\.colorScheme) private var colorScheme

    @State private var phase: LoadPhase = .loading
    @State private var original = ""
    @State private var modified = ""

    private enum LoadPhase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private var language: CodeMirrorLanguage {
        let hint = FileLanguageHint.resolve(fileName: request.fileName)
        return CodeMirrorLanguage(languageHint: hint)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task(id: request.id) {
            await loadSides()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: request.kind.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(request.kind.tintColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(request.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(request.kind.shortCode)
                .font(.caption.weight(.bold).monospaced())
                .foregroundStyle(request.kind.tintColor)
            if let nodeID = project.root.find(path: request.path)?.id {
                Button {
                    session.openFile(nodeID)
                } label: {
                    Label("Open File", systemImage: "doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView("Loading diff…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Diff Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .ready:
            CodeMirrorHostView(
                text: modified,
                language: language,
                isDark: colorScheme == .dark,
                isEditable: false,
                mergeOriginal: original,
                bookmarkLines: [],
                preferSoftTextReplace: false
            )
            .padding(.horizontal, LayoutMetrics.editorHorizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadSides() async {
        phase = .loading
        original = ""
        modified = ""
        guard vfs.connectionState.isReady else {
            phase = .failed("VFS is not connected.")
            return
        }

        do {
            switch request.kind {
            case .added, .untracked:
                original = ""
                modified = try await readWorktree(path: request.path)
            case .deleted:
                original = try await readRevision(path: request.path)
                modified = ""
            case .renamed:
                let from = request.fromPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                original = try await readRevision(path: from.isEmpty ? request.path : from)
                modified = try await readWorktree(path: request.path)
            case .modified:
                original = try await readRevision(path: request.path)
                modified = try await readWorktree(path: request.path)
            }
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func readRevision(path: String) async throws -> String {
        let shown = try await vfs.gitShow(path: path, revision: "HEAD")
        if shown.binary {
            throw VFSError.rpc(code: -32000, message: "Binary file — cannot display merge diff.")
        }
        return shown.exists ? shown.content : ""
    }

    private func readWorktree(path: String) async throws -> String {
        do {
            return try await vfs.read(path: path).content
        } catch {
            // Deleted / missing worktree file → empty modified side.
            return ""
        }
    }
}
