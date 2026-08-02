//
//  SidebarTreeRow.swift
//  HelmCode
//
//  Shared Files navigator row with depth indent + disclosure chevron.
//

import SwiftUI

struct SidebarTreeRow: View {
    let node: WorkspaceNode
    var depth: Int = 0
    var isExpanded: Bool = false
    var isSelected: Bool
    /// Toggle expand/collapse for directories (chevron tap).
    var onToggleExpand: (() -> Void)? = nil

    private enum Metrics {
        static let indentPerLevel: CGFloat = 14
        static let chevronWidth: CGFloat = 16
    }

    var body: some View {
        HStack(spacing: 6) {
            Color.clear
                .frame(width: CGFloat(depth) * Metrics.indentPerLevel)

            if node.isDirectory {
                Button {
                    onToggleExpand?()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: Metrics.chevronWidth, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            } else {
                Color.clear
                    .frame(width: Metrics.chevronWidth, height: 20)
            }

            FileTypeIcon(
                languageHint: node.languageHint,
                isDirectory: node.isDirectory,
                isSelected: isSelected,
                size: 18
            )
            .frame(width: 22, alignment: .center)

            Text(node.name)
                .lineLimit(1)
                .foregroundStyle(Color.primary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listItemTint(.primary)
        .tag(node.id)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(node.isDirectory ? (isExpanded ? "Expanded folder" : "Collapsed folder") : "File")
    }

    private var accessibilityTitle: String {
        if node.path.isEmpty { return node.name }
        return "\(node.name), \(node.path)"
    }
}
