//
//  SidebarBookmarksView.swift
//  HelmCode
//
//  Bookmarks navigator for the open project.
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
                        session.openFile(item.node.id)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.node.name)
                                    .lineLimit(1)
                                Text(item.node.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "bookmark.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contextMenu {
                        Button {
                            session.openFile(item.node.id)
                        } label: {
                            Label("Open", systemImage: "doc")
                        }
                        Button(role: .destructive) {
                            session.removeBookmark(item.bookmark)
                        } label: {
                            Label("Remove Bookmark", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    /// No icon; title + subtitle centered in the navigator area.
    private var emptyPlaceholder: some View {
        VStack(spacing: 6) {
            Text("No Bookmarks")
                .font(.headline)
            Text("Bookmark files from the Files navigator context menu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
