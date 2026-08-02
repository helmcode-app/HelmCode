//
//  SidebarBookmarksView.swift
//  HelmCode
//
//  Bookmarks navigator: whole-file/folder marks + line marks.
//  Leading icon is always the file/folder type icon (not a generic bookmark).
//

import SwiftUI

struct SidebarBookmarksView: View {
    @ObservedObject var session: WorkspaceSession

    @ViewBuilder
    var body: some View {
        let items = session.activeBookmarks
        if items.isEmpty {
            emptyPlaceholder
        } else {
            List {
                ForEach(items, id: \.bookmark.id) { item in
                    Button {
                        session.openBookmark(item.bookmark)
                    } label: {
                        Label {
                            bookmarkLabel(item.bookmark, node: item.node)
                        } icon: {
                            FileTypeIcon(
                                languageHint: item.node.languageHint,
                                isDirectory: item.node.isDirectory,
                                size: 18
                            )
                        }
                    }
                    .contextMenu {
                        Button {
                            session.openBookmark(item.bookmark)
                        } label: {
                            Label(
                                item.bookmark.isLineBookmark ? "Jump to Line" : "Open",
                                systemImage: "arrow.right.circle"
                            )
                        }
                        Button(role: .destructive) {
                            session.removeBookmark(item.bookmark)
                        } label: {
                            Label("Remove Bookmark", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .helmSidebarListStyle()
        }
    }

    @ViewBuilder
    private func bookmarkLabel(_ bookmark: WorkspaceBookmark, node: WorkspaceNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let line = bookmark.line {
                HStack(spacing: 6) {
                    Text(node.name)
                        .lineLimit(1)
                    Text(":\(line)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let snippet = bookmark.lineText, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(node.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(node.name)
                    .lineLimit(1)
                Text(node.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var emptyPlaceholder: some View {
        SidebarEmptyPlaceholder(
            title: "No Bookmarks",
            subtitle: "Bookmark a file from the Files context menu, or a line in the editor with ⌘ F2."
        )
    }
}
