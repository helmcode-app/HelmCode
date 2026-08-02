//
//  FileLanguageHint+ResolveTables.swift
//  HelmCode
//
//  Basename / extension → language hint tables (VS Code–style coverage).
//

import Foundation

extension FileLanguageHint {
    static func resolveSpecialBasename(_ lower: String) -> String? {
        switch lower {
        case "dockerfile", "containerfile": return "docker"
        case "go.mod", "go.sum": return "gomod"
        case "makefile", "gnumakefile", "makefile.am", "makefile.in": return "makefile"
        case "cmakelists.txt": return "cmake"
        case "gemfile", "gemfile.lock", "rakefile", "podfile", "fastfile": return "ruby"
        case "cargo.toml", "cargo.lock": return "rs"
        case "package.json": return "nodejs"
        case "package-lock.json", "npm-shrinkwrap.json": return "npm"
        case "yarn.lock": return "npm"
        case "pnpm-lock.yaml", "bun.lockb", "bun.lock": return "bun"
        case "tsconfig.json", "jsconfig.json": return "ts"
        case "composer.json", "composer.lock": return "php"
        case "requirements.txt", "pyproject.toml", "setup.py", "pipfile", "pipfile.lock": return "py"
        case "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle": return "java"
        case "cmakecache.txt": return "cmake"
        case ".gitignore", ".gitattributes", ".gitmodules": return "git"
        case ".dockerignore", ".npmignore", ".eslintignore", ".prettierignore": return "ignore"
        case ".env", ".env.local", ".env.development", ".env.production", ".env.test", ".env.example":
            return "env"
        case "procfile": return "procfile"
        case "webpack.config.js", "webpack.config.ts": return "webpack"
        case "vite.config.js", "vite.config.ts", "vite.config.mjs": return "vite"
        case "next.config.js", "next.config.mjs", "next.config.ts": return "nextjs"
        case "astro.config.mjs", "astro.config.ts": return "astro"
        case "angular.json": return "angular"
        case "nuxt.config.js", "nuxt.config.ts": return "vue"
        case "dockerfile.dev", "dockerfile.prod": return "docker"
        case "vagrantfile": return "ruby"
        case "jenkinsfile": return "groovy"
        case "terraform.tfstate", "terraform.tfvars": return "terraform"
        case "docker-compose.yml", "docker-compose.yaml", "compose.yml", "compose.yaml":
            return "docker"
        default:
            if lower.hasPrefix("dockerfile") { return "docker" }
            if lower.hasPrefix(".env.") { return "env" }
            if lower.hasSuffix(".tf") { return "terraform" }
            return nil
        }
    }

    static func resolveExtension(_ ext: String) -> String? {
        switch ext {
        // Swift / Apple
        case "swift": return "swift"
        case "m", "mm": return "objc"
        case "metal": return "metal"
        case "pbxproj", "xcconfig", "xcworkspacedata": return "swift"

        // Web / JS ecosystem
        case "ts", "mts", "cts": return "ts"
        case "tsx": return "tsx"
        case "js", "mjs", "cjs": return "js"
        case "jsx": return "jsx"
        case "html", "htm", "shtml", "xhtml": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "less": return "less"
        case "vue": return "vue"
        case "svelte": return "svelte"
        case "astro": return "astro"

        // Data / config
        case "json", "jsonc", "json5": return "json"
        case "yml", "yaml": return "yml"
        case "toml": return "toml"
        case "xml", "plist", "xsd", "xsl", "xslt", "dtd": return "xml"
        case "graphql", "gql": return "graphql"
        case "proto": return "proto"
        case "ini", "cfg", "conf", "properties", "editorconfig": return "ini"
        case "env": return "env"

        // Systems languages
        case "go": return "go"
        case "mod", "sum": return "gomod"
        case "rs": return "rs"
        case "py", "pyw", "pyi", "ipynb": return "py"
        case "rb", "rake", "gemspec", "ru": return "ruby"
        case "php", "phtml", "php3", "php4", "php5", "phps": return "php"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "scala", "sc": return "scala"
        case "cs", "csx": return "csharp"
        case "fs", "fsx", "fsi": return "fsharp"
        case "r", "rmd", "rdata": return "r"
        case "lua": return "lua"
        case "pl", "pm", "t", "pod": return "perl"
        case "ex", "exs": return "elixir"
        case "erl", "hrl": return "erlang"
        case "hs", "lhs": return "haskell"
        case "clj", "cljs", "cljc", "edn": return "clojure"
        case "dart": return "dart"
        case "zig": return "zig"
        case "nim", "nims": return "nim"
        case "jl": return "julia"
        case "matlab": return "matlab"
        case "sol": return "solidity"
        case "v", "sv": return "verilog"

        // C family
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "hh", "hxx", "ixx", "ipp": return "cpp"
        case "cu", "cuh": return "cuda"

        // Shell / devops
        case "sh", "bash", "zsh", "ksh", "fish", "command", "bats": return "sh"
        case "ps1", "psm1", "psd1": return "powershell"
        case "bat", "cmd": return "batch"
        case "dockerfile": return "docker"
        case "tf", "tfvars", "hcl": return "terraform"
        case "nginx": return "nginx"
        case "ansible": return "ansible"

        // Docs / markup
        case "md", "markdown", "mdown", "mkd", "mdx": return "md"
        case "rst", "rest": return "rst"
        case "tex", "latex", "sty", "cls", "bib": return "tex"
        case "adoc", "asciidoc": return "asciidoc"

        // SQL / data
        case "sql", "ddl", "dml": return "sql"
        case "sqlite", "db", "sqlite3": return "sqlite"
        case "csv", "tsv": return "csv"
        case "parquet": return "parquet"

        // Build / project
        case "gradle", "groovy": return "groovy"
        case "cmake": return "cmake"
        case "mk": return "makefile"
        case "lock": return "lock"

        // Misc
        case "diff", "patch": return "diff"
        case "svg": return "svg"
        case "wasm", "wat": return "wasm"
        case "gitignore", "gitattributes": return "git"

        default: return nil
        }
    }
}
