//
//  FileTypeIcon.swift
//  HelmCode
//
//  Sidebar file/folder glyph: Devicon brand asset or SF Symbol fallback.
//  Monochrome brand art uses template + language tint (readable in dark mode).
//

import SwiftUI

struct FileTypeIcon: View {
    let languageHint: String?
    var isDirectory: Bool = false
    var isSelected: Bool = false
    var size: CGFloat = 18

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
