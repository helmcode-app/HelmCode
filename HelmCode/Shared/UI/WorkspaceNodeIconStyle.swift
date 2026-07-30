//
//  WorkspaceNodeIconStyle.swift
//  HelmCode
//
//  Type-tinted SF Symbols for workspace file/folder rows.
//

import SwiftUI

enum WorkspaceNodeIconStyle {
    /// Idle (unselected) icon tint by kind / language.
    static func color(for node: WorkspaceNode) -> Color {
        if node.isDirectory { return .blue }
        switch node.languageHint {
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
