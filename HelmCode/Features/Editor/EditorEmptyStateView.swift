//
//  EditorEmptyStateView.swift
//  HelmCode
//
//  Center column when a project is open but no file is selected.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct EditorEmptyStateView: View {
    let project: WorkspaceProject
    var onOpenFile: (WorkspaceNode.ID) -> Void

    private var suggestedFiles: [WorkspaceNode] {
        project.root.collectFiles(limit: 6)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

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

            if !suggestedFiles.isEmpty {
                quickOpenSection
            }

            Spacer(minLength: 40)

            tipsBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private var projectChip: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Color.accentColor)
            Text(project.name)
                .font(.subheadline.weight(.medium))
            Text("·")
                .foregroundStyle(.tertiary)
            Text(project.defaultBranch)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var quickOpenSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionCaption(title: "Quick Open")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(suggestedFiles) { file in
                    Button {
                        onOpenFile(file.id)
                    } label: {
                        Label(file.name, systemImage: file.systemImage)
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 480)
        .padding(.top, 36)
        .padding(.horizontal, 32)
    }

    private var tipsBar: some View {
        HStack(spacing: 16) {
            Label("Browse files in the sidebar", systemImage: "sidebar.left")
            Label("Shortcuts in Settings → About", systemImage: "keyboard")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.bottom, 28)
        .padding(.horizontal, 24)
    }
}

#Preview {
    EditorEmptyStateView(
        project: WorkspaceCatalog.projects[0],
        onOpenFile: { _ in }
    )
}
