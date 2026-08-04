//
//  EditorEmptyStateView.swift
//  HelmCode
//
//  Center column when a project is open but no file is selected.
//  Quick Open uses the same FileTypeIcon pipeline as the sidebar.
//

import SwiftUI

struct EditorEmptyStateView: View {
    let project: WorkspaceProject
    var onOpenFile: (WorkspaceNode.ID) -> Void

    private enum Metrics {
        static let quickOpenLimit = 6
        static let contentMaxWidth: CGFloat = 480
        static let chipCorner: CGFloat = 10
    }

    private var suggestedFiles: [WorkspaceNode] {
        project.root.collectFiles(limit: Metrics.quickOpenLimit)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            hero
            if !suggestedFiles.isEmpty {
                quickOpenSection
            }
            Spacer(minLength: 40)
            tipsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("No File Open")
                    .font(.title2.weight(.semibold))
                Text("Select a file in the sidebar to start editing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            projectChip
        }
        .padding(.horizontal, 32)
    }

    private var projectChip: some View {
        HStack(spacing: 8) {
            ProjectAvatarIcon(project: project, size: ProjectAvatarMetrics.chip)
            Text(project.displayName)
                .font(.subheadline.weight(.medium))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(project.displayBranch)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    // MARK: - Quick Open

    private var quickOpenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Quick Open")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(suggestedFiles) { file in
                    quickOpenButton(file)
                }
            }
        }
        .frame(maxWidth: Metrics.contentMaxWidth)
        .padding(.top, 36)
        .padding(.horizontal, 32)
    }

    private func quickOpenButton(_ file: WorkspaceNode) -> some View {
        Button {
            onOpenFile(file.id)
        } label: {
            WorkspaceFileNameLabel(
                node: file,
                iconSize: FileTypeIconMetrics.compact
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: Metrics.chipCorner, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(file.name)")
    }

    // MARK: - Tips

    private var tipsBar: some View {
        HStack(spacing: 16) {
            Label("Browse files in the sidebar", systemImage: "sidebar.left")
            Label(EditorKeyboardShortcutsCatalog.emptyStateTip, systemImage: "keyboard")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 28)
        .padding(.horizontal, 24)
    }
}

#Preview {
    EditorEmptyStateView(
        project: WorkspaceCatalog.previewProject,
        onOpenFile: { _ in }
    )
}
