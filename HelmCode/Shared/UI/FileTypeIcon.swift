//
//  FileTypeIcon.swift
//  HelmCode
//
//  Shared file/folder glyph (sidebar tree, Quick Open, bookmarks, search).
//  Devicon brand asset or SF Symbol fallback; monochrome brands use template tint.
//

import SwiftUI

enum FileTypeIconMetrics {
    static let tree: CGFloat = 18
    static let list: CGFloat = 18
    static let compact: CGFloat = 16
}

struct FileTypeIcon: View {
    let languageHint: String?
    var isDirectory: Bool = false
    var isSelected: Bool = false
    var size: CGFloat = FileTypeIconMetrics.list

    init(
        languageHint: String?,
        isDirectory: Bool = false,
        isSelected: Bool = false,
        size: CGFloat = FileTypeIconMetrics.list
    ) {
        self.languageHint = languageHint
        self.isDirectory = isDirectory
        self.isSelected = isSelected
        self.size = size
    }

    /// Same glyph rules as the Files sidebar for a tree node.
    init(
        node: WorkspaceNode,
        isSelected: Bool = false,
        size: CGFloat = FileTypeIconMetrics.list
    ) {
        self.languageHint = node.languageHint
        self.isDirectory = node.isDirectory
        self.isSelected = isSelected
        self.size = size
    }

    var body: some View {
        if isDirectory {
            folderIcon
        } else if let asset = FileLanguageHint.assetImageName(forLanguageHint: languageHint) {
            brandAssetImage(asset)
        } else {
            symbolFallback
        }
    }

    // MARK: - Parts

    private var folderIcon: some View {
        Image(systemName: "folder.fill")
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(WorkspaceNodeIconStyle.folderColor)
            .font(.system(size: size * 0.95))
            .frame(width: size + 2, height: size + 2)
    }

    private var symbolFallback: some View {
        Image(systemName: FileLanguageHint.systemImageName(forLanguageHint: languageHint, filled: true))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(symbolTint)
            .font(.system(size: size * 0.95))
            .frame(width: size + 2, height: size + 2)
    }

    private var symbolTint: Color {
        isSelected
            ? Color.primary
            : WorkspaceNodeIconStyle.color(forLanguageHint: languageHint)
    }

    @ViewBuilder
    private func brandAssetImage(_ asset: String) -> some View {
        if FileLanguageHint.isMonochromeBrandAsset(forLanguageHint: languageHint) {
            Image(asset)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(WorkspaceNodeIconStyle.color(forLanguageHint: languageHint))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(asset)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Name + type icon row

/// Leading `FileTypeIcon` + file/folder name (Quick Open, compact lists).
struct WorkspaceFileNameLabel: View {
    let node: WorkspaceNode
    var iconSize: CGFloat = FileTypeIconMetrics.compact
    var isSelected: Bool = false
    var nameFont: Font = .subheadline

    var body: some View {
        HStack(spacing: 8) {
            FileTypeIcon(node: node, isSelected: isSelected, size: iconSize)
            Text(node.name)
                .font(nameFont)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}
