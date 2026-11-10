//
//  AgentMarkdownParser.swift
//  HelmCode
//
//  Maps apple/swift-markdown (cmark-gfm) AST → stable Equatable blocks for the Agent inspector.
//

import Foundation
import Markdown
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Render model

enum AgentMarkdownCallout: String, Equatable, Sendable {
    case note
    case tip
    case important
    case warning
    case caution

    init?(marker: String) {
        switch marker.uppercased() {
        case "NOTE": self = .note
        case "TIP": self = .tip
        case "IMPORTANT": self = .important
        case "WARNING": self = .warning
        case "CAUTION": self = .caution
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        }
    }

    var systemImage: String {
        switch self {
        case .note: return "info.circle.fill"
        case .tip: return "lightbulb.fill"
        case .important: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .caution: return "flame.fill"
        }
    }
}

enum AgentMarkdownColumnAlignment: Equatable, Sendable {
    case left, center, right, leading
}

struct AgentMarkdownListItem: Identifiable, Equatable, Sendable {
    let id: String
    /// `nil` = plain bullet/number; `true`/`false` = task checkbox.
    let checked: Bool?
    let blocks: [AgentMarkdownBlock]
}

enum AgentMarkdownListKind: Equatable, Sendable {
    case unordered
    case ordered(start: Int)
}

enum AgentMarkdownBlock: Identifiable, Equatable, Sendable {
    case heading(id: String, level: Int, text: AttributedString)
    case paragraph(id: String, text: AttributedString)
    case code(id: String, language: String?, path: String?, code: String)
    case quote(id: String, callout: AgentMarkdownCallout?, children: [AgentMarkdownBlock])
    case list(id: String, kind: AgentMarkdownListKind, items: [AgentMarkdownListItem])
    case table(
        id: String,
        alignments: [AgentMarkdownColumnAlignment],
        headers: [AttributedString],
        rows: [[AttributedString]]
    )
    case divider(id: String)
    case html(id: String, raw: String)

    var id: String {
        switch self {
        case .heading(let id, _, _),
             .paragraph(let id, _),
             .code(let id, _, _, _),
             .quote(let id, _, _),
             .list(let id, _, _),
             .table(let id, _, _, _),
             .divider(let id),
             .html(let id, _):
            return id
        }
    }
}

// MARK: - Fence info (`swift path/File.swift`, `swift:File.swift`, bare paths)

enum AgentFenceInfo {
    static func parse(_ raw: String?) -> (language: String?, path: String?) {
        guard var info = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !info.isEmpty else {
            return (nil, nil)
        }

        // Drop trailing attribute bags: ```swift {cmd=true}
        if let brace = info.firstIndex(of: "{") {
            info = String(info[..<brace]).trimmingCharacters(in: .whitespaces)
            if info.isEmpty { return (nil, nil) }
        }

        // `lang:path/with/slashes.ext` (colon form) — keep `C++` / `objective-c` intact.
        if let colon = info.firstIndex(of: ":") {
            let left = String(info[..<colon]).trimmingCharacters(in: .whitespaces)
            let right = String(info[info.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if looksLikePath(right), !left.isEmpty {
                return (normalizeLanguageToken(left), normalizePath(right))
            }
        }

        let parts = info.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = parts.first else { return (nil, nil) }

        if parts.count >= 2 {
            let rest = parts.dropFirst().joined(separator: " ")
            if looksLikePath(rest) {
                return (normalizeLanguageToken(first), normalizePath(rest))
            }
        }

        if looksLikePath(first), !isKnownLanguage(first) {
            return (languageFromPath(first), normalizePath(first))
        }

        return (normalizeLanguageToken(first), nil)
    }

    /// Pull a path from the first comment / File: line when the fence info has none.
    static func pathFromCodePreface(_ code: String) -> String? {
        guard let firstLine = code.split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map(String.init)
        else { return nil }

        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let prefixes = ["// ", "# ", "/// ", "-- ", "/* ", "*", "File:", "file:", "Path:", "path:"]
        for prefix in prefixes {
            guard trimmed.hasPrefix(prefix) else { continue }
            var rest = String(trimmed.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
            if rest.hasSuffix("*/") {
                rest = String(rest.dropLast(2)).trimmingCharacters(in: .whitespaces)
            }
            if looksLikePath(rest) { return normalizePath(rest) }
        }
        return nil
    }

    private static func looksLikePath(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains("\n") else { return false }
        if s.contains("/") { return true }
        if s.contains("."), let ext = s.split(separator: ".").last, (2...8).contains(ext.count) {
            return ext.allSatisfy({ $0.isLetter || $0.isNumber })
        }
        return false
    }

    private static func normalizePath(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "`\"'"))
        while s.hasPrefix("./") { s = String(s.dropFirst(2)) }
        return s
    }

    private static func normalizeLanguageToken(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private static func languageFromPath(_ path: String) -> String? {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let ext = name.split(separator: ".").last.map(String.init)?.lowercased() else {
            return nil
        }
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx": return "typescript"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "py": return "python"
        case "go": return "go"
        case "rs": return "rust"
        case "rb": return "ruby"
        case "kt", "kts": return "kotlin"
        case "cs": return "csharp"
        case "sh", "bash", "zsh": return "shell"
        case "yml", "yaml": return "yaml"
        case "json": return "json"
        case "md", "markdown": return "markdown"
        case "html", "htm": return "html"
        case "css": return "css"
        case "m", "mm": return "objc"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "c", "h": return "c"
        default: return ext
        }
    }

    private static func isKnownLanguage(_ token: String) -> Bool {
        let t = token.lowercased()
        let known: Set<String> = [
            "swift", "javascript", "js", "typescript", "ts", "tsx", "jsx", "python", "py",
            "go", "golang", "rust", "rs", "ruby", "rb", "shell", "bash", "sh", "zsh",
            "json", "yaml", "yml", "html", "css", "xml", "markdown", "md", "mermaid",
            "kotlin", "kt", "csharp", "cs", "c", "cpp", "objc", "sql", "diff", "text",
            "plaintext", "plain",
        ]
        return known.contains(t)
    }
}

// MARK: - Parse cache (skip identical re-parses during SwiftUI re-renders)

enum AgentMarkdownParseCache {
    private static var lastSource: String?
    private static var lastBlocks: [AgentMarkdownBlock] = []

    static func blocks(for source: String) -> [AgentMarkdownBlock] {
        if source == lastSource {
            return lastBlocks
        }
        let blocks = AgentMarkdownParser.blocks(from: source)
        lastSource = source
        lastBlocks = blocks
        return blocks
    }
}

// MARK: - Parser

enum AgentMarkdownParser {
    static func blocks(from source: String) -> [AgentMarkdownBlock] {
        let document = Document(parsing: source)
        var counter = 0
        return convertBlocks(document.blockChildren, idCounter: &counter)
    }

    // MARK: Blocks

    private static func convertBlocks(
        _ children: some Sequence<BlockMarkup>,
        idCounter: inout Int
    ) -> [AgentMarkdownBlock] {
        var result: [AgentMarkdownBlock] = []
        for child in children {
            if let block = convertBlock(child, idCounter: &idCounter) {
                result.append(block)
            }
        }
        return result
    }

    private static func convertBlock(_ markup: BlockMarkup, idCounter: inout Int) -> AgentMarkdownBlock? {
        switch markup {
        case let heading as Heading:
            return .heading(
                id: nextID(&idCounter),
                level: heading.level,
                text: attributedInlines(heading.inlineChildren)
            )

        case let paragraph as Paragraph:
            let text = attributedInlines(paragraph.inlineChildren)
            guard !String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return .paragraph(id: nextID(&idCounter), text: text)

        case let codeBlock as CodeBlock:
            var code = codeBlock.code
            if code.hasSuffix("\n") {
                code.removeLast()
            }
            let fence = AgentFenceInfo.parse(codeBlock.language)
            let path = fence.path ?? AgentFenceInfo.pathFromCodePreface(code)
            return .code(
                id: nextID(&idCounter),
                language: fence.language,
                path: path,
                code: code
            )

        case let quote as BlockQuote:
            return convertQuote(quote, idCounter: &idCounter)

        case let list as UnorderedList:
            return convertList(list, kind: .unordered, idCounter: &idCounter)

        case let list as OrderedList:
            return convertList(list, kind: .ordered(start: Int(list.startIndex)), idCounter: &idCounter)

        case let table as Markdown.Table:
            return convertTable(table, idCounter: &idCounter)

        case is ThematicBreak:
            return .divider(id: nextID(&idCounter))

        case let html as HTMLBlock:
            let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return .html(id: nextID(&idCounter), raw: raw)

        default:
            if let container = markup as? BlockContainer {
                let nested = convertBlocks(container.blockChildren, idCounter: &idCounter)
                if nested.count == 1 { return nested[0] }
                if !nested.isEmpty {
                    return .quote(id: nextID(&idCounter), callout: nil, children: nested)
                }
            }
            return nil
        }
    }

    private static func convertQuote(_ quote: BlockQuote, idCounter: inout Int) -> AgentMarkdownBlock {
        var children = convertBlocks(quote.blockChildren, idCounter: &idCounter)
        var callout: AgentMarkdownCallout?

        if let first = children.first, case .paragraph(let pid, let text) = first {
            if let detected = extractCallout(from: text) {
                callout = detected.callout
                if String(detected.remainder.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                {
                    children.removeFirst()
                } else {
                    children[0] = .paragraph(id: pid, text: detected.remainder)
                }
            }
        }

        return .quote(id: nextID(&idCounter), callout: callout, children: children)
    }

    private static func convertList(
        _ list: some ListItemContainer,
        kind: AgentMarkdownListKind,
        idCounter: inout Int
    ) -> AgentMarkdownBlock {
        var items: [AgentMarkdownListItem] = []
        for item in list.listItems {
            let checked: Bool? = {
                switch item.checkbox {
                case .checked: return true
                case .unchecked: return false
                case nil: return nil
                }
            }()
            let blocks = convertBlocks(item.blockChildren, idCounter: &idCounter)
            items.append(
                AgentMarkdownListItem(id: nextID(&idCounter), checked: checked, blocks: blocks)
            )
        }
        return .list(id: nextID(&idCounter), kind: kind, items: items)
    }

    private static func convertTable(_ table: Markdown.Table, idCounter: inout Int) -> AgentMarkdownBlock {
        let headers: [AttributedString] = Array(
            table.head.cells.map { attributedInlines($0.inlineChildren) }
        )
        let rows: [[AttributedString]] = Array(
            table.body.rows.map { row in
                Array(row.cells.map { attributedInlines($0.inlineChildren) })
            }
        )
        let headerCount = headers.count
        let maxRowCount = rows.map(\.count).max() ?? 0
        let alignmentCount = table.columnAlignments.count
        let columnCount = max(headerCount, max(maxRowCount, alignmentCount))

        var alignments: [AgentMarkdownColumnAlignment] = table.columnAlignments.map { alignment in
            switch alignment {
            case .left?: return .left
            case .center?: return .center
            case .right?: return .right
            case nil: return .leading
            }
        }
        if alignments.count < columnCount {
            alignments.append(
                contentsOf: Array(repeating: .leading, count: columnCount - alignments.count)
            )
        }

        return .table(
            id: nextID(&idCounter),
            alignments: alignments,
            headers: headers,
            rows: rows
        )
    }

    // MARK: Callout

    private static func extractCallout(
        from text: AttributedString
    ) -> (callout: AgentMarkdownCallout, remainder: AttributedString)? {
        let plain = String(text.characters)
        guard plain.hasPrefix("[!") else { return nil }
        guard let close = plain.firstIndex(of: "]") else { return nil }
        let markerStart = plain.index(plain.startIndex, offsetBy: 2)
        guard markerStart < close else { return nil }
        let marker = String(plain[markerStart..<close])
        guard let callout = AgentMarkdownCallout(marker: marker) else { return nil }

        var end = plain.index(after: close)
        while end < plain.endIndex {
            let ch = plain[end]
            if ch == " " || ch == "\t" {
                end = plain.index(after: end)
            } else {
                break
            }
        }

        // Callout marker is plain ASCII; remainder formatting on that first line is rarely critical.
        let remainder = AttributedString(String(plain[end...]))
        return (callout, remainder)
    }

    // MARK: Inlines

    private static func attributedInlines(
        _ inlines: some Sequence<InlineMarkup>
    ) -> AttributedString {
        var result = AttributedString()
        for inline in inlines {
            result.append(attributedInline(inline))
        }
        return result
    }

    private static func attributedInline(_ inline: InlineMarkup) -> AttributedString {
        switch inline {
        case let text as Markdown.Text:
            return AttributedString(text.string)

        case is SoftBreak:
            return AttributedString(" ")

        case is LineBreak:
            return AttributedString("\n")

        case let code as InlineCode:
            var run = AttributedString(code.code)
            #if canImport(UIKit)
            let size = UIFont.preferredFont(forTextStyle: .caption1).pointSize
            run.font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            run.backgroundColor = UIColor.tertiarySystemFill
            #endif
            return run

        case let strong as Strong:
            var run = attributedInlines(strong.inlineChildren)
            run.inlinePresentationIntent = mergedIntent(run.inlinePresentationIntent, .stronglyEmphasized)
            return run

        case let emphasis as Emphasis:
            var run = attributedInlines(emphasis.inlineChildren)
            run.inlinePresentationIntent = mergedIntent(run.inlinePresentationIntent, .emphasized)
            return run

        case let strike as Strikethrough:
            var run = attributedInlines(strike.inlineChildren)
            run.inlinePresentationIntent = mergedIntent(run.inlinePresentationIntent, .strikethrough)
            return run

        case let link as Markdown.Link:
            var run = attributedInlines(link.inlineChildren)
            if let destination = link.destination, let url = URL(string: destination) {
                run.link = url
            }
            run.underlineStyle = NSUnderlineStyle.single
            return run

        case let image as Markdown.Image:
            let alt = image.plainText
            if alt.isEmpty {
                return AttributedString(image.source ?? "")
            }
            return AttributedString(alt)

        case let html as InlineHTML:
            return AttributedString(html.rawHTML)

        case let symbol as SymbolLink:
            var run = AttributedString(symbol.destination ?? "")
            #if canImport(UIKit)
            let size = UIFont.preferredFont(forTextStyle: .caption1).pointSize
            run.font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            #endif
            return run

        default:
            if let container = inline as? InlineContainer {
                return attributedInlines(container.inlineChildren)
            }
            return AttributedString((inline as PlainTextConvertibleMarkup).plainText)
        }
    }

    private static func mergedIntent(
        _ existing: InlinePresentationIntent?,
        _ adding: InlinePresentationIntent
    ) -> InlinePresentationIntent {
        if let existing {
            return existing.union(adding)
        }
        return adding
    }

    private static func nextID(_ counter: inout Int) -> String {
        defer { counter += 1 }
        return "b\(counter)"
    }
}
