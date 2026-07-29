//
//  SidebarFilesView.swift
//  HelmCode
//
//  Files navigator: outline tree + context-menu file operations.
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
        return Label {
            HStack(spacing: 6) {
                Text(node.name)
                    .lineLimit(1)
                if session.isBookmarked(node.id) {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                }
            }
        } icon: {
            Image(systemName: node.systemImage)
                .foregroundStyle(Self.iconColor(for: node, isSelected: isSelected))
        }
        .tag(node.id)
        .accessibilityLabel(node.path)
        .contextMenu {
            fileContextMenu(node)
        }
    }

    /// Directory icons use accent blue when idle; selection chrome is also blue, so flip to white when selected.
    private static func iconColor(for node: WorkspaceNode, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return node.isDirectory ? Color.accentColor : Color.secondary
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
            session.toggleBookmark(nodeID: node.id)
        } label: {
            Label(
                session.isBookmarked(node.id) ? "Remove Bookmark" : "Bookmark",
                systemImage: session.isBookmarked(node.id) ? "bookmark.slash" : "bookmark"
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
