//
//  CodeMirrorLanguage.swift
//  HelmCode
//
//  Maps `FileLanguageHint` ids → bundled CM6 `languageExtension` keys
//  (`editor-entry.mjs` `languageExtension(lang)`).
//

import Foundation

enum CodeMirrorLanguage: String, Sendable, CaseIterable {
    case swift
    case typescript = "ts"
    case tsx
    case javascript = "js"
    case jsx
    case json
    case markdown = "md"
    case html
    case css
    case scss
    case go
    case gomod
    case python = "py"
    case rust = "rs"
    case java
    case kotlin
    case csharp
    case cpp
    case c
    case xml
    case yaml = "yml"
    case toml
    case sql
    case shell = "sh"
    case docker
    case ruby
    case php
    case lua
    case plain

    /// Bridge from sidebar/tree language hints into a CM mode id.
    init(languageHint: String?) {
        guard let hint = languageHint, !hint.isEmpty else {
            self = .plain
            return
        }
        // Prefer exact CM rawValue when the hint already matches a mode key.
        if let exact = CodeMirrorLanguage(rawValue: hint) {
            self = exact
            return
        }
        switch hint {
        case "html", "vue", "svelte": self = .html
        case "css", "less": self = .css
        case "java", "scala": self = .java
        case "csharp", "fsharp": self = .csharp
        case "cpp", "cuda", "objc", "metal": self = .cpp
        case "xml", "svg", "plist", "proto": self = .xml
        case "yml", "yaml": self = .yaml
        case "toml", "ini", "env", "hcl", "ignore", "lock", "procfile": self = .toml
        case "sh", "powershell", "batch", "makefile", "cmake": self = .shell
        case "ruby", "elixir", "perl": self = .ruby
        case "md", "markdown": self = .markdown
        case "py", "python": self = .python
        case "rs", "rust": self = .rust
        case "ts", "typescript": self = .typescript
        case "js", "javascript": self = .javascript
        default: self = .plain
        }
    }

    /// Wire id sent to `HelmCodeEditor.setDocument({ language })`.
    var bridgeID: String { rawValue }

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .typescript: return "TypeScript"
        case .tsx: return "TSX"
        case .javascript: return "JavaScript"
        case .jsx: return "JSX"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .html: return "HTML"
        case .css: return "CSS"
        case .scss: return "SCSS"
        case .go: return "Go"
        case .gomod: return "Go Module"
        case .python: return "Python"
        case .rust: return "Rust"
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .csharp: return "C#"
        case .cpp: return "C/C++"
        case .c: return "C"
        case .xml: return "XML"
        case .yaml: return "YAML"
        case .toml: return "TOML"
        case .sql: return "SQL"
        case .shell: return "Shell"
        case .docker: return "Dockerfile"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .lua: return "Lua"
        case .plain: return "Plain Text"
        }
    }
}
