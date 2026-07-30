//
//  SidebarFilesView.swift
//  HelmCode
//
//  Files navigator: outline tree + context-menu file operations.
//  Context menu Bookmark = whole file/folder (original). No trailing badge icon.
//  Line bookmarks are added from the editor only.
//

import SwiftUI

struct SidebarFilesView: View {
    @ObservedObject var session: WorkspaceSession
    let project: WorkspaceProject
    var onPresentDialog: (SidebarTreeDialog) -> Void

    var body: some View {
        List(selection: $session.selectedFileID) {
            OutlineGroup(project.root.children, children: \.directoryChildren) { node in
                fileRow(node)
            }
        }
        .listStyle(.sidebar)
    }

    private func fileRow(_ node: WorkspaceNode) -> some View {
        let isSelected = session.selectedFileID == node.id
        return HStack(spacing: 8) {
            Image(systemName: node.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    isSelected ? Color.primary : WorkspaceNodeIconStyle.color(for: node)
                )
                .frame(width: 20, alignment: .center)

            Text(node.name)
                .lineLimit(1)
                .foregroundStyle(Color.primary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listItemTint(.primary)
        .tag(node.id)
        .accessibilityLabel(node.path)
        .contextMenu {
            fileContextMenu(node)
        }
    }

    @ViewBuilder
    private func fileContextMenu(_ node: WorkspaceNode) -> some View {
        if !node.isDirectory {
            Button {
                session.openFile(node.id)
            } label: {
                Label("Open", systemImage: "doc")
            }
        }

        Button {
            onPresentDialog(.newFile(anchorID: node.id))
        } label: {
            Label("New File…", systemImage: "doc.badge.plus")
        }

        Button {
            onPresentDialog(.newFolder(anchorID: node.id))
        } label: {
            Label("New Folder…", systemImage: "folder.badge.plus")
        }

        Divider()

        Button {
            onPresentDialog(.rename(nodeID: node.id, currentName: node.name))
        } label: {
            Label("Rename…", systemImage: "pencil")
        }

        Button {
            session.toggleFileBookmark(nodeID: node.id)
        } label: {
            Label(
                session.isFileBookmarked(node.id) ? "Remove Bookmark" : "Bookmark",
                systemImage: session.isFileBookmarked(node.id) ? "bookmark.slash" : "bookmark"
            )
        }

        Divider()

        Button(role: .destructive) {
            onPresentDialog(.delete(nodeID: node.id, name: node.name, isDirectory: node.isDirectory))
        } label: {
            Label("Delete…", systemImage: "trash")
        }
    }
}
