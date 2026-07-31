//
//  SidebarTreeRow.swift
//  HelmCode
//
//  Shared Files navigator row (catalog + VFS both use WorkspaceNode).
//

import SwiftUI

struct SidebarTreeRow: View {
    let node: WorkspaceNode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.sidebarSystemImage)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(WorkspaceNodeIconStyle.color(for: node, isSelected: isSelected))
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
    }
}
