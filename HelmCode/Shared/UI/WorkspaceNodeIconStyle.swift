//
//  WorkspaceNodeIconStyle.swift
//  HelmCode
//
//  Type-tinted SF Symbols for workspace file/folder rows.
//

import SwiftUI

enum WorkspaceNodeIconStyle {
    /// Idle (unselected) icon tint by node kind / language.
    /// Directories use amber (sidebar tree + bookmarks + search).
    static func color(for node: WorkspaceNode) -> Color {
        if node.isDirectory { return .orange }
        return color(forLanguageHint: node.languageHint)
    }

    /// Selected list row: match title color (primary), not type tint.
    static func color(for node: WorkspaceNode, isSelected: Bool) -> Color {
        isSelected ? .primary : color(for: node)
    }

    /// SF Symbol for a language hint (or generic file).
    static func systemImage(forLanguageHint hint: String?) -> String {
        FileLanguageHint.systemImageName(forLanguageHint: hint, filled: false)
    }

    /// Idle icon tint from language hint only (search headers, etc.).
    static func color(forLanguageHint hint: String?) -> Color {
        switch hint {
        case "swift": return .orange
        case "objc", "metal": return Color(red: 0.55, green: 0.55, blue: 0.58)
        case "ts", "tsx": return Color(red: 0.20, green: 0.48, blue: 0.86)
        case "js", "jsx": return Color(red: 0.94, green: 0.79, blue: 0.18)
        case "html", "vue", "svelte": return Color(red: 0.89, green: 0.35, blue: 0.13)
        case "css", "scss", "less": return Color(red: 0.20, green: 0.45, blue: 0.86)
        case "json", "graphql": return .green
        case "yml", "yaml": return .indigo
        case "toml", "ini", "env", "hcl": return Color(red: 0.55, green: 0.45, blue: 0.75)
        case "xml", "svg", "plist": return Color(red: 0.90, green: 0.55, blue: 0.15)
        case "md", "rst", "tex", "asciidoc": return .purple
        case "go", "gomod": return .cyan
        case "rs": return Color(red: 0.87, green: 0.38, blue: 0.16)
        case "py": return Color(red: 0.22, green: 0.46, blue: 0.69)
        case "java", "kotlin", "scala": return Color(red: 0.85, green: 0.35, blue: 0.20)
        case "csharp", "fsharp": return Color(red: 0.35, green: 0.55, blue: 0.85)
        case "c", "cpp", "cuda": return Color(red: 0.35, green: 0.55, blue: 0.90)
        case "sh", "powershell", "batch", "makefile", "cmake": return .mint
        case "docker": return Color(red: 0.15, green: 0.55, blue: 0.85)
        case "sql": return Color(red: 0.35, green: 0.65, blue: 0.75)
        case "ruby": return Color(red: 0.80, green: 0.15, blue: 0.15)
        case "php": return Color(red: 0.45, green: 0.40, blue: 0.75)
        case "dart": return Color(red: 0.20, green: 0.70, blue: 0.90)
        case "diff", "patch": return .secondary
        case "ignore", "lock", "procfile": return .secondary
        case "proto": return Color(red: 0.40, green: 0.70, blue: 0.45)
        default: return .secondary
        }
    }
}
