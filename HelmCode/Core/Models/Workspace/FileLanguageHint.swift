//
//  FileLanguageHint.swift
//  HelmCode
//
//  Shared file-extension → language hint + SF Symbol names (catalog + VFS trees).
//

import Foundation

enum FileLanguageHint {
    /// Language id from a file name (extension only); directories yield nil upstream.
    static func resolve(fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "ts"
        case "js", "jsx", "mjs", "cjs": return "js"
        case "json": return "json"
        case "md", "markdown": return "md"
        case "go": return "go"
        case "py": return "py"
        case "rs": return "rs"
        case "html", "htm": return "html"
        case "css", "scss": return "css"
        case "yml", "yaml": return "yml"
        case "sh", "bash", "zsh": return "sh"
        case "c", "h", "cpp", "hpp", "cc", "mm", "m": return "cpp"
        default: return nil
        }
    }

    /// SF Symbol name for a language hint (or generic file document).
    static func systemImageName(forLanguageHint hint: String?, filled: Bool = false) -> String {
        switch hint {
        case "swift": return "swift"
        case "ts", "js": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md": return "doc.richtext"
        case "go": return "chevron.left.forwardslash.chevron.right"
        default: return filled ? "doc.text.fill" : "doc.text"
        }
    }
}
