//
//  FileLanguageHint.swift
//  HelmCode
//
//  file name → language hint id (sidebar icons + CodeMirrorLanguage).
//  Brand assets: FileLanguageHint+BrandAssets · colors: WorkspaceNodeIconStyle · UI: FileTypeIcon.
//

import Foundation

enum FileLanguageHint {
    // MARK: - Resolve

    /// Language id from a file name (special basenames first, then extension).
    static func resolve(fileName: String) -> String? {
        let base = (fileName as NSString).lastPathComponent
        let lower = base.lowercased()

        if let special = resolveSpecialBasename(lower) {
            return special
        }

        let ext = (base as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return resolveExtension(ext)
    }

    /// SF Symbol fallback when no brand asset is available.
    static func systemImageName(forLanguageHint hint: String?, filled: Bool = false) -> String {
        let generic = filled ? "doc.text.fill" : "doc.text"
        switch hint {
        case "swift": return "swift"
        case "objc", "metal": return "apple.logo"
        case "ts", "tsx", "js", "jsx": return "curlybraces"
        case "html", "vue", "svelte", "react", "angular", "astro", "nextjs":
            return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "less": return "paintbrush"
        case "json", "graphql": return "curlybraces.square"
        case "yml", "yaml", "toml", "ini", "env", "hcl", "terraform":
            return "list.bullet.rectangle"
        case "xml", "svg", "plist": return "chevron.left.slash.chevron.right"
        case "md", "rst", "tex", "asciidoc": return "doc.richtext"
        case "go", "gomod": return "arrow.triangle.branch"
        case "rs": return "gearshape.2"
        case "py", "django", "flask", "fastapi": return "chevron.left.forwardslash.chevron.right"
        case "java", "kotlin", "scala", "csharp", "fsharp", "spring": return "cup.and.saucer"
        case "c", "cpp", "cuda": return "c.circle"
        case "sh", "powershell", "batch", "makefile", "cmake": return "terminal"
        case "docker": return "shippingbox"
        case "sql", "sqlite", "postgresql", "mysql": return "cylinder.split.1x2"
        case "ruby", "php", "perl", "lua", "elixir", "erlang", "haskell", "clojure",
             "dart", "zig", "nim", "r", "julia", "matlab", "solidity":
            return "chevron.left.forwardslash.chevron.right"
        case "diff", "patch": return "plus.forwardslash.minus"
        case "ignore", "lock", "procfile": return "eye.slash"
        case "proto": return "network"
        case "git": return "arrow.triangle.branch"
        case "nodejs", "npm", "webpack", "vite", "bun": return "shippingbox"
        case "nginx": return "server.rack"
        case "wasm": return "cpu"
        default: return generic
        }
    }
}
