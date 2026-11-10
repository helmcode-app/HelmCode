//
//  AgentCodeHighlighter.swift
//  HelmCode
//
//  Lightweight single-pass lexer for agent code fences (no external highlighter deps).
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum AgentCodeHighlighter {
    enum TokenKind: Equatable {
        case plain
        case keyword
        case string
        case comment
        case number
        case typeName
    }

    static func highlight(
        code: String,
        language: String?,
        colorScheme: ColorScheme
    ) -> AttributedString {
        guard !code.isEmpty else { return AttributedString(" ") }

        let lang = normalizedLanguage(language)
        let keywords = keywordSet(for: lang)
        let palette = Palette(colorScheme: colorScheme)

        var result = AttributedString()
        var i = code.startIndex

        while i < code.endIndex {
            // Line / block comments
            if let comment = matchComment(in: code, from: i, language: lang) {
                result.append(colored(String(code[comment]), kind: .comment, palette: palette))
                i = comment.upperBound
                continue
            }

            // Strings
            if let stringRange = matchString(in: code, from: i, language: lang) {
                result.append(colored(String(code[stringRange]), kind: .string, palette: palette))
                i = stringRange.upperBound
                continue
            }

            let ch = code[i]

            // Numbers
            if ch.isNumber || (ch == "." && peekIsDigit(code, after: i)) {
                let end = scanNumber(in: code, from: i)
                result.append(colored(String(code[i..<end]), kind: .number, palette: palette))
                i = end
                continue
            }

            // Identifiers / keywords / types
            if ch.isLetter || ch == "_" || ch == "$" {
                let end = scanIdentifier(in: code, from: i)
                let word = String(code[i..<end])
                let kind: TokenKind
                if keywords.contains(word) {
                    kind = .keyword
                } else if looksLikeTypeName(word, language: lang) {
                    kind = .typeName
                } else {
                    kind = .plain
                }
                result.append(colored(word, kind: kind, palette: palette))
                i = end
                continue
            }

            // Single punctuation / whitespace
            result.append(colored(String(ch), kind: .plain, palette: palette))
            i = code.index(after: i)
        }

        return result
    }

    // MARK: - Language

    private static func normalizedLanguage(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "plain" }
        switch raw.lowercased() {
        case "js", "javascript", "jsx", "mjs", "cjs": return "javascript"
        case "ts", "typescript", "tsx": return "typescript"
        case "py", "python3": return "python"
        case "rb", "ruby": return "ruby"
        case "sh", "bash", "zsh", "shell", "shellscript": return "shell"
        case "yml": return "yaml"
        case "golang": return "go"
        case "rs": return "rust"
        case "c++", "cplusplus": return "cpp"
        case "objc", "objective-c", "objectivec": return "objc"
        case "kt", "kts": return "kotlin"
        case "cs", "csharp": return "csharp"
        case "md", "markdown": return "markdown"
        default: return raw.lowercased()
        }
    }

    private static func keywordSet(for language: String) -> Set<String> {
        switch language {
        case "swift":
            return [
                "associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func",
                "import", "init", "inout", "internal", "let", "open", "operator", "private",
                "protocol", "public", "rethrows", "static", "struct", "subscript", "typealias",
                "var", "break", "case", "catch", "continue", "default", "defer", "do", "else",
                "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw", "throws",
                "switch", "where", "while", "as", "any", "false", "is", "nil", "self", "Self",
                "super", "true", "try", "async", "await", "actor", "nonisolated", "isolated",
                "some", "borrowing", "consuming", "package", "macro", "each",
            ]
        case "typescript", "javascript":
            return [
                "abstract", "as", "async", "await", "break", "case", "catch", "class", "const",
                "continue", "debugger", "default", "delete", "do", "else", "enum", "export",
                "extends", "false", "finally", "for", "from", "function", "get", "if", "implements",
                "import", "in", "instanceof", "interface", "let", "new", "null", "of", "package",
                "private", "protected", "public", "return", "set", "static", "super", "switch",
                "this", "throw", "true", "try", "typeof", "var", "void", "while", "with", "yield",
                "type", "namespace", "readonly", "declare", "keyof", "infer", "satisfies",
            ]
        case "python":
            return [
                "False", "None", "True", "and", "as", "assert", "async", "await", "break",
                "class", "continue", "def", "del", "elif", "else", "except", "finally", "for",
                "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or",
                "pass", "raise", "return", "try", "while", "with", "yield", "match", "case",
            ]
        case "go":
            return [
                "break", "case", "chan", "const", "continue", "default", "defer", "else",
                "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
                "package", "range", "return", "select", "struct", "switch", "type", "var",
                "true", "false", "nil",
            ]
        case "rust":
            return [
                "as", "async", "await", "break", "const", "continue", "crate", "dyn", "else",
                "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop",
                "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static",
                "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while",
            ]
        case "shell":
            return [
                "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case",
                "esac", "function", "select", "until", "in", "time", "coproc", "export",
                "local", "return", "exit", "true", "false",
            ]
        case "ruby":
            return [
                "alias", "and", "begin", "break", "case", "class", "def", "defined?", "do",
                "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next",
                "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super",
                "then", "true", "undef", "unless", "until", "when", "while", "yield",
            ]
        case "kotlin":
            return [
                "as", "break", "class", "continue", "do", "else", "false", "for", "fun", "if",
                "in", "interface", "is", "null", "object", "package", "return", "super", "this",
                "throw", "true", "try", "typealias", "typeof", "val", "var", "when", "while",
                "by", "catch", "constructor", "delegate", "dynamic", "field", "file", "finally",
                "get", "import", "init", "param", "property", "receiver", "set", "setparam",
                "where", "actual", "abstract", "annotation", "companion", "const", "crossinline",
                "data", "enum", "expect", "external", "final", "infix", "inline", "inner",
                "internal", "lateinit", "noinline", "open", "operator", "out", "override",
                "private", "protected", "public", "reified", "sealed", "suspend", "tailrec",
                "vararg",
            ]
        case "csharp":
            return [
                "abstract", "as", "base", "bool", "break", "byte", "case", "catch", "char",
                "checked", "class", "const", "continue", "decimal", "default", "delegate", "do",
                "double", "else", "enum", "event", "explicit", "extern", "false", "finally",
                "fixed", "float", "for", "foreach", "goto", "if", "implicit", "in", "int",
                "interface", "internal", "is", "lock", "long", "namespace", "new", "null",
                "object", "operator", "out", "override", "params", "private", "protected",
                "public", "readonly", "ref", "return", "sbyte", "sealed", "short", "sizeof",
                "stackalloc", "static", "string", "struct", "switch", "this", "throw", "true",
                "try", "typeof", "uint", "ulong", "unchecked", "unsafe", "ushort", "using",
                "virtual", "void", "volatile", "while", "async", "await", "var", "record",
                "when", "nameof", "notnull", "nint", "nuint",
            ]
        case "json":
            return ["true", "false", "null"]
        default:
            return [
                "if", "else", "for", "while", "return", "class", "struct", "enum", "func",
                "function", "var", "let", "const", "true", "false", "null", "nil", "import",
                "export", "async", "await", "switch", "case", "break", "continue", "try",
                "catch", "throw", "new", "this", "self",
            ]
        }
    }

    private static func looksLikeTypeName(_ word: String, language: String) -> Bool {
        guard let first = word.first, first.isUppercase else { return false }
        switch language {
        case "swift", "typescript", "javascript", "go", "rust", "kotlin", "csharp", "ruby":
            return word.count > 1
        default:
            return false
        }
    }

    // MARK: - Scanners

    private static func matchComment(
        in code: String,
        from i: String.Index,
        language: String
    ) -> Range<String.Index>? {
        guard i < code.endIndex else { return nil }
        let next = code.index(after: i)

        if language == "python" || language == "yaml" || language == "shell" || language == "ruby" {
            if code[i] == "#" {
                return i..<(code[i...].firstIndex(of: "\n") ?? code.endIndex)
            }
        }

        if language == "html" || language == "xml" || language == "markdown" {
            if code[i...].hasPrefix("<!--") {
                if let end = code.range(of: "-->", range: i..<code.endIndex) {
                    return i..<end.upperBound
                }
                return i..<code.endIndex
            }
        }

        // C-family // and /* */
        if ["swift", "javascript", "typescript", "go", "rust", "kotlin", "csharp", "cpp", "objc", "plain"]
            .contains(language)
            || !["python", "yaml", "shell", "ruby", "json"].contains(language)
        {
            if code[i] == "/", next < code.endIndex, code[next] == "/" {
                return i..<(code[i...].firstIndex(of: "\n") ?? code.endIndex)
            }
            if code[i] == "/", next < code.endIndex, code[next] == "*" {
                var j = code.index(next, offsetBy: 1)
                while j < code.endIndex {
                    let n = code.index(after: j)
                    if code[j] == "*", n < code.endIndex, code[n] == "/" {
                        return i..<code.index(after: n)
                    }
                    j = n
                }
                return i..<code.endIndex
            }
        }

        return nil
    }

    private static func matchString(
        in code: String,
        from i: String.Index,
        language: String
    ) -> Range<String.Index>? {
        guard i < code.endIndex else { return nil }
        let ch = code[i]

        // Python / JS triple quotes
        if (language == "python" || language == "javascript" || language == "typescript"),
           code[i...].hasPrefix("\"\"\"") || code[i...].hasPrefix("'''")
        {
            let quote = String(code[i...].prefix(3))
            let searchFrom = code.index(i, offsetBy: 3)
            if let end = code.range(of: quote, range: searchFrom..<code.endIndex) {
                return i..<end.upperBound
            }
            return i..<code.endIndex
        }

        // Swift raw strings #"..."#
        if language == "swift", ch == "#" {
            var hashes = 0
            var j = i
            while j < code.endIndex, code[j] == "#" {
                hashes += 1
                j = code.index(after: j)
            }
            if j < code.endIndex, code[j] == "\"" {
                let closer = "\"" + String(repeating: "#", count: hashes)
                let searchFrom = code.index(after: j)
                if let end = code.range(of: closer, range: searchFrom..<code.endIndex) {
                    return i..<end.upperBound
                }
                return i..<code.endIndex
            }
        }

        guard ch == "\"" || ch == "'" || ch == "`" else { return nil }

        // Template literals / backtick strings
        var j = code.index(after: i)
        var escaped = false
        while j < code.endIndex {
            let c = code[j]
            if escaped {
                escaped = false
                j = code.index(after: j)
                continue
            }
            if c == "\\" {
                escaped = true
                j = code.index(after: j)
                continue
            }
            if c == ch {
                return i..<code.index(after: j)
            }
            // Unclosed line string for single quotes in shell often spans one line — keep scanning.
            j = code.index(after: j)
        }
        return i..<code.endIndex
    }

    private static func scanIdentifier(in code: String, from i: String.Index) -> String.Index {
        var j = code.index(after: i)
        while j < code.endIndex {
            let c = code[j]
            if c.isLetter || c.isNumber || c == "_" || c == "$" {
                j = code.index(after: j)
            } else {
                break
            }
        }
        return j
    }

    private static func scanNumber(in code: String, from i: String.Index) -> String.Index {
        var j = i
        var sawDot = false
        while j < code.endIndex {
            let c = code[j]
            if c.isNumber {
                j = code.index(after: j)
            } else if c == ".", !sawDot {
                let next = code.index(after: j)
                guard next < code.endIndex, code[next].isNumber else { break }
                sawDot = true
                j = next
            } else if c == "_" {
                j = code.index(after: j)
            } else {
                break
            }
        }
        return j
    }

    private static func peekIsDigit(_ code: String, after i: String.Index) -> Bool {
        let next = code.index(after: i)
        return next < code.endIndex && code[next].isNumber
    }

    // MARK: - Styling

    private struct Palette {
        #if canImport(UIKit)
        let keyword: UIColor
        let string: UIColor
        let comment: UIColor
        let number: UIColor
        let typeName: UIColor
        let plain: UIColor
        #else
        let keyword: Color
        let string: Color
        let comment: Color
        let number: Color
        let typeName: Color
        let plain: Color
        #endif

        init(colorScheme: ColorScheme) {
            let dark = colorScheme == .dark
            #if canImport(UIKit)
            // UIColor attributes render reliably in SwiftUI `Text(AttributedString)`.
            keyword = dark
                ? UIColor(red: 0.78, green: 0.47, blue: 0.90, alpha: 1)
                : UIColor(red: 0.55, green: 0.15, blue: 0.65, alpha: 1)
            string = dark
                ? UIColor(red: 0.95, green: 0.55, blue: 0.42, alpha: 1)
                : UIColor(red: 0.75, green: 0.22, blue: 0.17, alpha: 1)
            comment = UIColor.secondaryLabel
            number = dark
                ? UIColor(red: 0.45, green: 0.72, blue: 0.98, alpha: 1)
                : UIColor(red: 0.15, green: 0.40, blue: 0.75, alpha: 1)
            typeName = dark
                ? UIColor(red: 0.55, green: 0.85, blue: 0.75, alpha: 1)
                : UIColor(red: 0.10, green: 0.50, blue: 0.45, alpha: 1)
            plain = UIColor.label
            #else
            keyword = dark ? Color(red: 0.78, green: 0.47, blue: 0.90) : Color(red: 0.55, green: 0.15, blue: 0.65)
            string = dark ? Color(red: 0.95, green: 0.55, blue: 0.42) : Color(red: 0.75, green: 0.22, blue: 0.17)
            comment = Color.secondary
            number = dark ? Color(red: 0.45, green: 0.72, blue: 0.98) : Color(red: 0.15, green: 0.40, blue: 0.75)
            typeName = dark ? Color(red: 0.55, green: 0.85, blue: 0.75) : Color(red: 0.10, green: 0.50, blue: 0.45)
            plain = Color.primary
            #endif
        }

        #if canImport(UIKit)
        func color(for kind: TokenKind) -> UIColor {
            switch kind {
            case .plain: return plain
            case .keyword: return keyword
            case .string: return string
            case .comment: return comment
            case .number: return number
            case .typeName: return typeName
            }
        }
        #else
        func color(for kind: TokenKind) -> Color {
            switch kind {
            case .plain: return plain
            case .keyword: return keyword
            case .string: return string
            case .comment: return comment
            case .number: return number
            case .typeName: return typeName
            }
        }
        #endif
    }

    private static func colored(_ text: String, kind: TokenKind, palette: Palette) -> AttributedString {
        var run = AttributedString(text)
        run.foregroundColor = palette.color(for: kind)
        return run
    }
}
