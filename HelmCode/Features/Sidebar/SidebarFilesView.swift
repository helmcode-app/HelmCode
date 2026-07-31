//
//  SidebarFilesView.swift
//  HelmCode
//
//  Files navigator: OutlineGroup tree + context menu.
//  Tap file leaf → vfs/read over WebSocket → editor buffer.
//

import SwiftUI

struct SidebarFilesView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var vfs: VFSNetworkEngine
    let project: WorkspaceProject
    var onPresentDialog: (SidebarTreeDialog) -> Void

    var body: some View {
        List(selection: Binding(
            get: { session.selectedFileID },
            set: { newValue in
                session.selectedFileID = newValue
                if let newValue {
                    Task { await openSelection(newValue) }
                }
            }
        )) {
            if let tree = vfs.tree, project.id == WorkspaceSession.vfsProjectID {
                OutlineGroup(tree.children, children: \.directoryChildren) { node in
                    treeRow(node)
                }
            } else {
                OutlineGroup(project.root.children, children: \.directoryChildren) { node in
                    fileRow(node)
                }
            }
        }
        .helmSidebarListStyle()
        .overlay(alignment: .bottom) {
            if project.id == WorkspaceSession.vfsProjectID {
                vfsStatusStrip
            }
        }
    }

    // MARK: - VFS tree rows

    private func treeRow(_ node: WorkspaceTreeNode) -> some View {
        let isSelected = session.selectedFileID == node.id
        return HStack(spacing: 8) {
            Image(systemName: node.systemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    isSelected
                        ? Color.primary
                        : (node.isDirectory ? Color.orange : Color.blue)
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
            if !node.isDirectory {
                Button {
                    Task { await openVFSPath(node.path, nodeID: node.id) }
                } label: {
                    Label("Open", systemImage: "doc")
                }
            }
        }
    }

    // MARK: - Catalog (demo) tree rows

    private func fileRow(_ node: WorkspaceNode) -> some View {
        let isSelected = session.selectedFileID == node.id
        return HStack(spacing: 8) {
            Image(systemName: node.isDirectory ? node.systemImage : FileLanguageHint.systemImageName(forLanguageHint: node.languageHint, filled: true))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(
                    isSelected
                        ? Color.primary
                        : (node.isDirectory ? Color.orange : WorkspaceNodeIconStyle.color(for: node))
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

    // MARK: - Open

    private func openSelection(_ id: WorkspaceNode.ID) async {
        if project.id == WorkspaceSession.vfsProjectID {
            if let path = session.vfsPath(forNodeID: id) ?? vfs.tree?.find(id: id)?.path {
                // Directories only expand in OutlineGroup; skip read.
                if let node = vfs.tree?.find(id: id), node.isDirectory { return }
                if let node = project.root.find(id: id), node.isDirectory { return }
                await openVFSPath(path, nodeID: id)
            }
        } else {
            session.openFile(id)
        }
    }

    private func openVFSPath(_ path: String, nodeID: WorkspaceNode.ID) async {
        session.openFile(nodeID)
        guard !path.isEmpty else { return }
        do {
            _ = try await vfs.read(path: path)
        } catch {
            session.lastTreeError = error.localizedDescription
        }
    }

    private var vfsStatusStrip: some View {
        Text(vfs.connectionState.shortTitle)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(.bar)
            .allowsHitTesting(false)
    }
}
