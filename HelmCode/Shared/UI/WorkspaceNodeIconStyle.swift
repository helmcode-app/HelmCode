//
//  WorkspaceNodeIconStyle.swift
//  HelmCode
//
//  Type-tinted SF Symbols for workspace file/folder rows.
//

import SwiftUI

enum WorkspaceNodeIconStyle {
    /// Idle (unselected) icon tint by node kind / language.
    static func color(for node: WorkspaceNode) -> Color {
        if node.isDirectory { return .blue }
        return color(forLanguageHint: node.languageHint)
    }

    /// SF Symbol for a language hint (or generic file).
    static func systemImage(forLanguageHint hint: String?) -> String {
        switch hint {
        case "swift": return "swift"
        case "ts", "js": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md": return "doc.richtext"
        case "go": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    /// Idle icon tint from language hint only (search headers, etc.).
    static func color(forLanguageHint hint: String?) -> Color {
        switch hint {
        case "swift": return .orange
        case "ts": return Color(red: 0.20, green: 0.48, blue: 0.86)
        case "js": return Color(red: 0.94, green: 0.79, blue: 0.18)
        case "json": return .green
        case "md": return .purple
        case "go": return .cyan
        case "html", "css": return .pink
        case "py": return Color(red: 0.22, green: 0.46, blue: 0.69)
        case "rs": return Color(red: 0.87, green: 0.38, blue: 0.16)
        case "yml", "yaml": return .indigo
        case "sh", "bash": return .mint
        default: return .secondary
        }
    }
}
