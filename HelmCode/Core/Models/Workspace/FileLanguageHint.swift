//
//  FileLanguageHint.swift
//  HelmCode
//
//  file name → language hint id (sidebar icons + CodeMirrorLanguage).
//  Keep ids short and stable; map to CM modes in `CodeMirrorLanguage`.
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

    /// SF Symbol name for a language hint (or generic file document).
    static func systemImageName(forLanguageHint hint: String?, filled: Bool = false) -> String {
        let generic = filled ? "doc.text.fill" : "doc.text"
        switch hint {
        case "swift": return "swift"
        case "objc", "metal": return "apple.logo"
        case "ts", "tsx", "js", "jsx": return "curlybraces"
        case "html", "vue", "svelte": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "less": return "paintbrush"
        case "json", "graphql": return "curlybraces.square"
        case "yml", "yaml", "toml", "ini", "env", "hcl": return "list.bullet.rectangle"
        case "xml", "svg", "plist": return "chevron.left.slash.chevron.right"
        case "md", "rst", "tex", "asciidoc": return "doc.richtext"
        case "go", "gomod": return "arrow.triangle.branch"
        case "rs": return "gearshape.2"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "java", "kotlin", "scala", "csharp", "fsharp": return "cup.and.saucer"
        case "c", "cpp", "cuda": return "c.circle"
        case "sh", "powershell", "batch", "makefile", "cmake": return "terminal"
        case "docker": return "shippingbox"
        case "sql": return "cylinder.split.1x2"
        case "ruby", "php", "perl", "lua", "elixir", "erlang", "haskell", "clojure", "dart", "zig", "nim", "r":
            return "chevron.left.forwardslash.chevron.right"
        case "diff", "patch": return "plus.forwardslash.minus"
        case "ignore", "lock", "procfile": return "eye.slash"
        case "proto": return "network"
        default: return generic
        }
    }

    // MARK: - Basename / extension tables

    private static func resolveSpecialBasename(_ lower: String) -> String? {
        switch lower {
        case "dockerfile", "containerfile": return "docker"
        case "go.mod", "go.sum": return "gomod"
        case "makefile", "gnumakefile", "makefile.am", "makefile.in": return "makefile"
        case "cmakelists.txt": return "cmake"
        case "gemfile", "rakefile", "podfile", "fastfile": return "ruby"
        case "cargo.toml", "cargo.lock": return "toml"
        case "package.json", "tsconfig.json", "jsconfig.json", "composer.json": return "json"
        case ".gitignore", ".dockerignore", ".npmignore", ".eslintignore": return "ignore"
        case ".env", ".env.local", ".env.development", ".env.production", ".env.test": return "env"
        case "procfile": return "procfile"
        default:
            if lower.hasPrefix("dockerfile.") { return "docker" }
            if lower.hasPrefix(".env.") { return "env" }
            return nil
        }
    }

    private static func resolveExtension(_ ext: String) -> String? {
        switch ext {
        case "swift": return "swift"
        case "m", "mm": return "objc"
        case "metal": return "metal"

        case "ts", "mts", "cts": return "ts"
        case "tsx": return "tsx"
        case "js", "mjs", "cjs": return "js"
        case "jsx": return "jsx"
        case "html", "htm", "shtml": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "less": return "less"
        case "vue": return "vue"
        case "svelte": return "svelte"

        case "json", "jsonc", "json5": return "json"
        case "yml", "yaml": return "yml"
        case "toml": return "toml"
        case "xml", "plist", "xsd", "xsl", "xslt": return "xml"
        case "graphql", "gql": return "graphql"
        case "proto": return "proto"
        case "ini", "cfg", "conf", "properties": return "ini"
        case "env": return "env"

        case "go": return "go"
        case "mod": return "gomod"
        case "rs": return "rs"
        case "py", "pyw", "pyi": return "py"
        case "rb", "rake": return "ruby"
        case "php": return "php"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "scala", "sc": return "scala"
        case "cs": return "csharp"
        case "fs", "fsx", "fsi": return "fsharp"
        case "r": return "r"
        case "lua": return "lua"
        case "pl", "pm": return "perl"
        case "ex", "exs": return "elixir"
        case "erl", "hrl": return "erlang"
        case "hs", "lhs": return "haskell"
        case "clj", "cljs", "cljc": return "clojure"
        case "dart": return "dart"
        case "zig": return "zig"
        case "nim": return "nim"

        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "ixx": return "cpp"
        case "cu", "cuh": return "cuda"

        case "sh", "bash", "zsh", "ksh", "fish", "command": return "sh"
        case "ps1", "psm1", "psd1": return "powershell"
        case "bat", "cmd": return "batch"
        case "dockerfile": return "docker"
        case "tf", "tfvars", "hcl": return "hcl"
        case "nginx": return "nginx"

        case "md", "markdown", "mdown", "mkd": return "md"
        case "rst": return "rst"
        case "tex", "latex", "sty", "cls": return "tex"
        case "adoc", "asciidoc": return "asciidoc"

        case "sql": return "sql"
        case "csv", "tsv": return "csv"

        case "gradle", "groovy": return "groovy"
        case "cmake": return "cmake"
        case "mk": return "makefile"
        case "lock": return "lock"

        case "diff", "patch": return "diff"
        case "svg": return "svg"
        case "wasm": return "wasm"

        default: return nil
        }
    }
}
