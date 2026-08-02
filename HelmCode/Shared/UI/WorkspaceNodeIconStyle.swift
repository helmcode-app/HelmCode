//
//  WorkspaceNodeIconStyle.swift
//  HelmCode
//
//  Language → accent color for SF Symbol fallbacks and monochrome brand templates.
//  Multicolor Devicon PNGs keep original pixels (see FileTypeIcon).
//

import SwiftUI

enum WorkspaceNodeIconStyle {
    static let folderColor: Color = .orange

    static func color(forLanguageHint hint: String?) -> Color {
        switch hint {
        case "swift": return .orange
        case "objc", "metal": return Color(red: 0.55, green: 0.55, blue: 0.58)
        case "ts", "tsx": return Color(red: 0.20, green: 0.48, blue: 0.86)
        case "js", "jsx": return Color(red: 0.94, green: 0.79, blue: 0.18)
        case "html", "vue", "svelte", "react", "angular", "astro", "nextjs":
            return Color(red: 0.89, green: 0.35, blue: 0.13)
        case "css", "scss", "less": return Color(red: 0.20, green: 0.45, blue: 0.86)
        case "json", "graphql": return .green
        case "yml", "yaml", "terraform": return .indigo
        case "toml", "ini", "env", "hcl": return Color(red: 0.55, green: 0.45, blue: 0.75)
        case "xml", "svg", "plist": return Color(red: 0.90, green: 0.55, blue: 0.15)
        case "md", "rst", "tex", "asciidoc": return .purple
        case "go", "gomod": return .cyan
        case "rs": return Color(red: 0.87, green: 0.38, blue: 0.16)
        case "py", "django", "flask", "fastapi": return Color(red: 0.22, green: 0.46, blue: 0.69)
        case "java", "kotlin", "scala", "spring": return Color(red: 0.85, green: 0.35, blue: 0.20)
        case "csharp", "fsharp": return Color(red: 0.35, green: 0.55, blue: 0.85)
        case "c", "cpp", "cuda": return Color(red: 0.35, green: 0.55, blue: 0.90)
        case "sh", "powershell", "batch", "makefile", "cmake": return .mint
        case "docker": return Color(red: 0.15, green: 0.55, blue: 0.85)
        case "sql", "sqlite", "postgresql", "mysql": return Color(red: 0.35, green: 0.65, blue: 0.75)
        case "ruby": return Color(red: 0.80, green: 0.15, blue: 0.15)
        case "php": return Color(red: 0.45, green: 0.40, blue: 0.75)
        case "dart": return Color(red: 0.20, green: 0.70, blue: 0.90)
        case "solidity": return Color(red: 0.55, green: 0.45, blue: 0.85)
        case "ansible": return Color(red: 0.85, green: 0.20, blue: 0.20)
        default: return .secondary
        }
    }
}
