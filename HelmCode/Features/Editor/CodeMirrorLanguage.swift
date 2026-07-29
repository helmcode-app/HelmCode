//
//  CodeMirrorLanguage.swift
//  HelmCode
//
//  Language ids accepted by bundled CM6 `languageExtension`.
//

import Foundation

enum CodeMirrorLanguage: String, Sendable, CaseIterable {
    case swift
    case typescript = "ts"
    case javascript = "js"
    case json
    case markdown = "md"
    case go
    case cpp
    case plain

    init(languageHint: String?) {
        switch languageHint {
        case "swift": self = .swift
        case "ts": self = .typescript
        case "js": self = .javascript
        case "json": self = .json
        case "md": self = .markdown
        case "go": self = .go
        case "cpp", "c": self = .cpp
        default: self = .plain
        }
    }

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .json: return "JSON"
        case .markdown: return "Markdown"
        case .go: return "Go"
        case .cpp: return "C/C++"
        case .plain: return "Plain Text"
        }
    }
}
