//
//  SidebarFilesView.swift
//  HelmCode
//
//  Files navigator: expandable tree with pointer + keyboard navigation.
//  ←/→ expand·collapse, ↑/↓ move (+ auto-scroll), ↵ open file.
//  Navigation math: `SidebarFileTreeKeyboard` · flatten: `SidebarFileTreeModel`.
//

import SwiftUI

struct SidebarFilesView: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var vfs: VFSNetworkEngine
    let project: WorkspaceProject
    var onPresentDialog: (SidebarTreeDialog) -> Void

    /// Expanded directory ids for the open project.
    @State var expandedIDs: Set<WorkspaceNode.ID> = []
    @FocusState var treeFocused: Bool

    var isVFS: Bool { project.isVFSRemote }

    var rows: [SidebarFileTreeRow] {
        SidebarFileTreeModel.visibleRows(
            roots: project.root.children,
            expandedIDs: expandedIDs
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selectionBinding) {
                ForEach(rows) { row in
                    SidebarTreeRow(
                        node: row.node,
                        depth: row.depth,
                        isExpanded: expandedIDs.contains(row.node.id),
                        isSelected: session.selectedFileID == row.node.id,
                        onToggleExpand: row.node.isDirectory
                            ? { toggleExpanded(row.node.id) }
                            : nil
                    )
                    .id(row.id)
                    .contextMenu { contextMenu(for: row.node) }
                }
            }
            .helmSidebarListStyle()
            .modifier(SidebarFileTreeFocusChrome(treeFocused: $treeFocused))
            .onAppear {
                treeFocused = true
                expandSelectionAncestors()
                scrollToSelection(proxy, id: session.selectedFileID)
            }
            .onChange(of: project.id) { _, _ in
                expandedIDs = []
                treeFocused = true
            }
            .onChange(of: session.selectedFileID) { _, newID in
                guard let newID else { return }
                expandAncestors(of: newID)
                scrollToSelection(proxy, id: newID)
            }
            .onChange(of: expandedIDs) { _, _ in
                scrollToSelection(proxy, id: session.selectedFileID)
            }
            .modifier(SidebarFileTreeKeyHandlers(onAction: handleKeyboardAction))
            .accessibilityHint("Use arrow keys to move and expand folders. Return opens a file.")
        }
    }

    // MARK: - Selection

    private var selectionBinding: Binding<WorkspaceNode.ID?> {
        Binding(
            get: { session.selectedFileID },
            set: { newValue in
                session.selectedFileID = newValue
                treeFocused = true
                if let newValue {
                    Task { await openSelection(newValue) }
                }
            }
        )
    }

    // MARK: - Keyboard routing

    private func handleKeyboardAction(_ key: SidebarFileTreeKey) {
        switch key {
        case .left:
            apply(SidebarFileTreeKeyboard.leftArrow(
                selected: selectedNode(),
                expandedIDs: expandedIDs,
                root: project.root
            ))
        case .right:
            apply(SidebarFileTreeKeyboard.rightArrow(
                selected: selectedNode(),
                expandedIDs: expandedIDs
            ))
        case .up:
            apply(SidebarFileTreeKeyboard.move(
                delta: -1,
                selectedID: session.selectedFileID,
                rows: rows
            ))
        case .down:
            apply(SidebarFileTreeKeyboard.move(
                delta: 1,
                selectedID: session.selectedFileID,
                rows: rows
            ))
        case .returnKey:
            openCurrentSelection()
        case .space:
            if let node = selectedNode(), node.isDirectory {
                toggleExpanded(node.id)
            } else {
                openCurrentSelection()
            }
        }
    }

    private func apply(_ action: SidebarFileTreeKeyboard.Action) {
        switch action {
        case .expand(let id):
            expandedIDs.insert(id)
        case .collapse(let id):
            expandedIDs.remove(id)
        case .select(let id):
            session.selectedFileID = id
        case .selectAndOpen(let id):
            session.selectedFileID = id
            Task { await openSelection(id) }
        case .openCurrent:
            openCurrentSelection()
        case .none:
            break
        }
    }

    // MARK: - Scroll

    func scrollToSelection(_ proxy: ScrollViewProxy, id: WorkspaceNode.ID?) {
        guard let id else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.12)) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.5))
            }
        }
    }

    // MARK: - Expand

    func toggleExpanded(_ id: WorkspaceNode.ID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    func expandSelectionAncestors() {
        guard let id = session.selectedFileID else { return }
        expandAncestors(of: id)
    }

    func expandAncestors(of id: WorkspaceNode.ID) {
        SidebarFileTreeModel.expandingAncestors(of: id, in: project.root, into: &expandedIDs)
    }

    func selectedNode() -> WorkspaceNode? {
        guard let id = session.selectedFileID else { return nil }
        return project.root.find(id: id)
    }

    // MARK: - Open

    func openCurrentSelection() {
        guard let id = session.selectedFileID else { return }
        Task { await openSelection(id, forceOpenDirectory: false, forceOpenFile: true) }
    }

    func openSelection(
        _ id: WorkspaceNode.ID,
        forceOpenDirectory: Bool = false,
        forceOpenFile: Bool = false
    ) async {
        guard let node = project.root.find(id: id) else { return }
        if node.isDirectory {
            if forceOpenDirectory { toggleExpanded(id) }
            return
        }
        if isVFS {
            await openVFSPath(node.path, nodeID: id)
        } else {
            session.openFile(id)
        }
    }

    func openVFSPath(_ path: String, nodeID: WorkspaceNode.ID) async {
        session.openFile(nodeID)
        guard !path.isEmpty else { return }
        do {
            _ = try await vfs.read(path: path)
        } catch {
            let message = error.localizedDescription
            if message.contains("timed out") { return }
            session.lastTreeError = message
        }
    }

    // MARK: - Context menus

    @ViewBuilder
    func contextMenu(for node: WorkspaceNode) -> some View {
        if isVFS {
            vfsContextMenu(node)
        } else {
            catalogContextMenu(node)
        }
    }

    @ViewBuilder
    func vfsContextMenu(_ node: WorkspaceNode) -> some View {
        if !node.isDirectory {
            Button {
                Task { await openVFSPath(node.path, nodeID: node.id) }
            } label: {
                Label("Open", systemImage: "doc")
            }
        }
    }

    @ViewBuilder
    func catalogContextMenu(_ node: WorkspaceNode) -> some View {
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

// MARK: - Focus chrome (keyboard without blue ring)

private struct SidebarFileTreeFocusChrome: ViewModifier {
    var treeFocused: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused(treeFocused)
            .focusEffectDisabled()
    }
}

// MARK: - Key bindings

enum SidebarFileTreeKey: Equatable {
    case left, right, up, down, returnKey, space
}

private struct SidebarFileTreeKeyHandlers: ViewModifier {
    var onAction: (SidebarFileTreeKey) -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.leftArrow) { onAction(.left); return .handled }
            .onKeyPress(.rightArrow) { onAction(.right); return .handled }
            .onKeyPress(.upArrow) { onAction(.up); return .handled }
            .onKeyPress(.downArrow) { onAction(.down); return .handled }
            .onKeyPress(.return) { onAction(.returnKey); return .handled }
            .onKeyPress(.space) { onAction(.space); return .handled }
    }
}
