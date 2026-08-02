//
//  FileLanguageHint+BrandAssets.swift
//  HelmCode
//
//  Devicon imageset mapping under Assets.xcassets/FileTypeIcons/.
//  Prefer 1x/2x/3x PNG (original colors). Monochrome logos need template tint.
//

import Foundation

extension FileLanguageHint {
    /// Asset catalog name under `FileTypeIcons/` namespace when a Devicon is bundled.
    /// Example: `"FileTypeIcons/go"`.
    static func assetImageName(forLanguageHint hint: String?) -> String? {
        guard let key = assetKey(forLanguageHint: hint) else { return nil }
        return "FileTypeIcons/\(key)"
    }

    /// Brand glyphs that are black / near-monochrome in the source art.
    /// Drawn as **template** icons so dark mode can recolor them.
    static func isMonochromeBrandAsset(forLanguageHint hint: String?) -> Bool {
        guard let key = assetKey(forLanguageHint: hint) else { return false }
        return monochromeBrandAssetKeys.contains(key)
    }

    /// Imagesets whose pixels are black/gray (no usable brand hue on dark backgrounds).
    private static let monochromeBrandAssetKeys: Set<String> = [
        "markdown", "latex", "rust", "solidity", "flask", "nextjs",
        "bash", "ansible", "json", "github",
    ]

    /// Maps language hint → imageset name (without folder namespace).
    static func assetKey(forLanguageHint hint: String?) -> String? {
        switch hint {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx": return "javascript"
        case "html": return "html"
        case "css", "less": return "css"
        case "scss": return "sass"
        case "vue": return "vue"
        case "svelte": return "svelte"
        case "react": return "react"
        case "angular": return "angular"
        case "astro": return "astro"
        case "nextjs": return "nextjs"
        case "go", "gomod": return "go"
        case "py": return "python"
        case "django": return "django"
        case "flask": return "flask"
        case "fastapi": return "fastapi"
        case "rs": return "rust"
        case "java": return "java"
        case "kotlin": return "kotlin"
        case "scala": return "scala"
        case "csharp": return "csharp"
        case "fsharp": return "fsharp"
        case "c": return "c"
        case "cpp", "cuda": return "cplusplus"
        case "objc", "metal": return "objectivec"
        case "ruby": return "ruby"
        case "php": return "php"
        case "perl": return "perl"
        case "lua": return "lua"
        case "elixir": return "elixir"
        case "erlang": return "erlang"
        case "haskell": return "haskell"
        case "clojure": return "clojure"
        case "dart": return "dart"
        case "zig": return "zig"
        case "nim": return "nim"
        case "r": return "r"
        case "julia": return "julia"
        case "matlab": return "matlab"
        case "sh", "batch", "makefile": return "bash"
        case "powershell": return "powershell"
        case "docker": return "docker"
        case "cmake": return "cmake"
        case "md": return "markdown"
        case "tex": return "latex"
        case "yml", "yaml": return "yaml"
        case "xml", "svg", "plist": return "xml"
        case "json": return "json"
        case "sql", "sqlite": return "sqlite"
        case "postgresql": return "postgresql"
        case "mysql": return "mysql"
        case "graphql": return "graphql"
        case "hcl", "terraform": return "terraform"
        case "nginx": return "nginx"
        case "git": return "git"
        case "nodejs": return "nodejs"
        case "npm", "lock": return "npm"
        case "webpack": return "webpack"
        case "vite": return "vite"
        case "wasm": return "wasm"
        case "solidity": return "solidity"
        case "spring": return "spring"
        case "bun": return "bun"
        case "ansible": return "ansible"
        default: return nil
        }
    }
}
