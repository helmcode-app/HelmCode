//
//  SidebarFilesView.swift
//  HelmCode
//
//  Files navigator: OutlineGroup tree + context menu.
//  Runner-backed projects share the WorkspaceNode model for the outline tree.
//

import SwiftUI

struct SidebarFilesView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var vfs: VFSNetworkEngine
    let project: WorkspaceProject
    var onPresentDialog: (SidebarTreeDialog) -> Void

    private var isVFS: Bool { project.isVFSRemote }

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
            OutlineGroup(project.root.children, children: \.directoryChildren) { node in
                SidebarTreeRow(node: node, isSelected: session.selectedFileID == node.id)
                    .contextMenu {
                        if isVFS {
                            vfsContextMenu(node)
                        } else {
                            catalogContextMenu(node)
                        }
                    }
            }
        }
        .helmSidebarListStyle()
    }

    // MARK: - Context menus

    @ViewBuilder
    private func vfsContextMenu(_ node: WorkspaceNode) -> some View {
        if !node.isDirectory {
            Button {
                Task { await openVFSPath(node.path, nodeID: node.id) }
            } label: {
                Label("Open", systemImage: "doc")
            }
        }
    }

    @ViewBuilder
    private func catalogContextMenu(_ node: WorkspaceNode) -> some View {
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
        guard let node = project.root.find(id: id) else { return }
        if node.isDirectory { return }

        if isVFS {
            await openVFSPath(node.path, nodeID: id)
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
            // Transient WS timeouts are recovered by reconnect; avoid modal spam.
            let message = error.localizedDescription
            if message.contains("timed out") {
                return
            }
            session.lastTreeError = message
        }
    }
}
