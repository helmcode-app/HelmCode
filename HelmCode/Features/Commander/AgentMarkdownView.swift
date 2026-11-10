//
//  AgentMarkdownView.swift
//  HelmCode
//
//  Native SwiftUI renderer for agent answers — powered by AgentMarkdownParser.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentMarkdownView: View {
    let source: String
    var onOpenPath: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    private var blocks: [AgentMarkdownBlock] {
        AgentMarkdownParseCache.blocks(for: source)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                AgentMarkdownBlockView(
                    block: block,
                    colorScheme: colorScheme,
                    onOpenPath: onOpenPath
                )
                .equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Block cell (Equatable → skip unchanged ancestors while streaming)

private struct AgentMarkdownBlockView: View, Equatable {
    let block: AgentMarkdownBlock
    let colorScheme: ColorScheme
    var onOpenPath: ((String) -> Void)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block == rhs.block && lhs.colorScheme == rhs.colorScheme
    }

    @ViewBuilder
    var body: some View {
        switch block {
        case .heading(_, let level, let text):
            headingView(level: level, text: text)
        case .paragraph(_, let text):
            paragraphView(text)
        case .code(_, let language, let path, let code):
            if (language ?? "").lowercased() == "mermaid" {
                AgentMermaidView(source: code, colorScheme: colorScheme)
            } else {
                AgentMarkdownCodeFenceView(
                    language: language,
                    path: path,
                    code: code,
                    colorScheme: colorScheme,
                    onOpenPath: onOpenPath
                )
            }
        case .quote(_, let callout, let children):
            quoteView(callout: callout, children: children)
        case .list(_, let kind, let items):
            listView(kind: kind, items: items, depth: 0)
        case .table(_, let alignments, let headers, let rows):
            AgentMarkdownTableView(
                alignments: alignments,
                headers: headers,
                rows: rows,
                colorScheme: colorScheme
            )
        case .divider:
            dividerView
        case .html(_, let raw):
            htmlView(raw)
        }
    }

    // MARK: Heading / Paragraph

    private func headingView(level: Int, text: AttributedString) -> some View {
        let font: Font = {
            switch level {
            case 1: return .subheadline.weight(.bold)
            case 2: return .subheadline.weight(.semibold)
            case 3: return .footnote.weight(.semibold)
            default: return .caption.weight(.semibold)
            }
        }()

        return Text(text)
            .font(font)
            .foregroundStyle(.primary)
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, level <= 2 ? 6 : 2)
            .padding(.bottom, 1)
    }

    private func paragraphView(_ text: AttributedString) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.primary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Quote / Callout

    private func quoteView(callout: AgentMarkdownCallout?, children: [AgentMarkdownBlock]) -> AnyView {
        let tint = calloutTint(callout)

        return AnyView(
            HStack(alignment: .top, spacing: 0) {
                AgentAccentRail(tint: tint, width: 2.5)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    if let callout {
                        Label(callout.title, systemImage: callout.systemImage)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tint)
                            .labelStyle(.titleAndIcon)
                    }

                    ForEach(children) { child in
                        AgentMarkdownBlockView(
                            block: child,
                            colorScheme: colorScheme,
                            onOpenPath: onOpenPath
                        )
                        .equatable()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                (callout == nil ? Color(.secondarySystemFill) : tint.opacity(0.10))
                    .opacity(callout == nil ? 0.45 : 1),
                in: RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous))
        )
    }

    private func calloutTint(_ callout: AgentMarkdownCallout?) -> Color {
        switch callout {
        case .note: return Color.accentColor
        case .tip: return .green
        case .important: return .indigo
        case .warning: return .orange
        case .caution: return .red
        case nil: return Color.secondary.opacity(0.85)
        }
    }

    // MARK: Lists

    private func listView(kind: AgentMarkdownListKind, items: [AgentMarkdownListItem], depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    listItemRow(kind: kind, index: index, item: item, depth: depth)
                }
            }
            .padding(.leading, depth == 0 ? 0 : 14)
        )
    }

    private func listItemRow(
        kind: AgentMarkdownListKind,
        index: Int,
        item: AgentMarkdownListItem,
        depth: Int
    ) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 8) {
                listMarker(kind: kind, index: index, checked: item.checked, depth: depth)
                    .frame(width: 18, alignment: .trailing)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.blocks) { child in
                        if case .list(_, let nestedKind, let nestedItems) = child {
                            listView(kind: nestedKind, items: nestedItems, depth: depth + 1)
                        } else {
                            AgentMarkdownBlockView(
                                block: child,
                                colorScheme: colorScheme,
                                onOpenPath: onOpenPath
                            )
                            .equatable()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    @ViewBuilder
    private func listMarker(
        kind: AgentMarkdownListKind,
        index: Int,
        checked: Bool?,
        depth: Int
    ) -> some View {
        if let checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.caption.weight(.semibold))
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                .accessibilityLabel(checked ? "Completed" : "Incomplete")
        } else {
            switch kind {
            case .unordered:
                Text(depth == 0 ? "•" : "◦")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .ordered(let start):
                Text("\(start + index).")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Table

    // MARK: Misc

    private var dividerView: some View {
        Rectangle()
            .fill(AgentChrome.hairline(colorScheme))
            .frame(height: 1)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
    }

    private func htmlView(_ raw: String) -> some View {
        Text(raw)
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Code fence

private struct AgentMarkdownCodeFenceView: View {
    let language: String?
    let path: String?
    let code: String
    let colorScheme: ColorScheme
    var onOpenPath: ((String) -> Void)?

    @State private var justCopied = false

    private var lineCount: Int {
        if code.isEmpty { return 0 }
        return code.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private var showLineNumbers: Bool { lineCount > 3 }

    private var canOpen: Bool {
        guard let path, !path.isEmpty, onOpenPath != nil else { return false }
        return true
    }

    private var highlighted: AttributedString {
        AgentCodeHighlighter.highlight(code: code, language: language, colorScheme: colorScheme)
    }

    var body: some View {
        let lang = (language?.isEmpty == false) ? language! : "code"

        return HStack(alignment: .top, spacing: 0) {
            AgentAccentRail(tint: .secondary.opacity(0.9), width: 2)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text(lang)
                        .font(.caption2.weight(.bold).monospaced())
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if let path, !path.isEmpty {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 4)
                    if canOpen, let path {
                        Button {
                            onOpenPath?(path)
                        } label: {
                            Label("Open", systemImage: "arrow.up.right.square")
                                .font(.caption2.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(path) in editor")
                    }
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = code
                        #endif
                        withAnimation(AgentChrome.sendMorph) {
                            justCopied = true
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1200))
                            withAnimation(AgentChrome.sendMorph) {
                                justCopied = false
                            }
                        }
                    } label: {
                        Label(
                            justCopied ? "Copied" : "Copy",
                            systemImage: justCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption2.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(justCopied ? Color.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(justCopied ? "Copied code" : "Copy code")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Rectangle()
                    .fill(AgentChrome.hairline(colorScheme))
                    .frame(height: 1)
                    .accessibilityHidden(true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        if showLineNumbers {
                            lineNumberColumn
                        }

                        Text(highlighted)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, showLineNumbers ? 8 : 10)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
        .background(
            AgentChrome.codeFill,
            in: RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
                .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
        )
    }

    private var lineNumberColumn: some View {
        let width: CGFloat = lineCount >= 100 ? 28 : 22
        return Text(lineNumberText)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.trailing)
            .lineSpacing(0)
            .frame(width: width, alignment: .trailing)
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }

    private var lineNumberText: String {
        (1...max(lineCount, 1)).map { String($0) }.joined(separator: "\n")
    }
}

// MARK: - Table View with full-width stretching

private struct TableWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct AgentMarkdownTableView: View, Equatable {
    let alignments: [AgentMarkdownColumnAlignment]
    let headers: [AttributedString]
    let rows: [[AttributedString]]
    let colorScheme: ColorScheme

    @State private var containerWidth: CGFloat = 0

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.alignments == rhs.alignments &&
        lhs.headers == rhs.headers &&
        lhs.rows == rhs.rows &&
        lhs.colorScheme == rhs.colorScheme
    }

    private var columnCount: Int {
        max(headers.count, rows.map(\.count).max() ?? 0)
    }

    var body: some View {
        let widths = distributedWidths(for: containerWidth)

        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !headers.isEmpty {
                        tableRow(
                            cells: pad(headers, to: columnCount),
                            alignments: alignments,
                            widths: widths,
                            isHeader: true,
                            zebra: false
                        )
                        Rectangle()
                            .fill(AgentChrome.hairline(colorScheme))
                            .frame(height: 1)
                    }

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        tableRow(
                            cells: pad(row, to: columnCount),
                            alignments: alignments,
                            widths: widths,
                            isHeader: false,
                            zebra: rowIndex % 2 == 1
                        )
                    }
                }
                .frame(minWidth: containerWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: TableWidthPreferenceKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(TableWidthPreferenceKey.self) { newWidth in
            if newWidth > 0, abs(newWidth - containerWidth) > 1 {
                containerWidth = newWidth
            }
        }
        .background(
            AgentChrome.codeFill,
            in: RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChrome.codeRadius, style: .continuous)
                .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
        )
    }

    private func tableRow(
        cells: [AttributedString],
        alignments: [AgentMarkdownColumnAlignment],
        widths: [CGFloat],
        isHeader: Bool,
        zebra: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell)
                    .font(isHeader ? .caption2.weight(.bold) : .caption2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(textAlignment(alignments, index: index))
                    .frame(
                        width: widths[safe: index] ?? 80,
                        alignment: frameAlignment(alignments, index: index)
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, isHeader ? 7 : 6)
                    .textSelection(.enabled)

                if index < cells.count - 1 {
                    Rectangle()
                        .fill(AgentChrome.hairline(colorScheme))
                        .frame(width: 1)
                }
            }
        }
        .frame(minWidth: containerWidth, alignment: .leading)
        .background(
            isHeader
                ? Color(.secondarySystemFill).opacity(0.7)
                : (zebra ? Color(.tertiarySystemFill).opacity(0.45) : Color.clear)
        )
    }

    private func distributedWidths(for availableWidth: CGFloat) -> [CGFloat] {
        guard columnCount > 0 else { return [] }
        let charWidth: CGFloat = 6.6
        let horizontalPadding: CGFloat = 20
        let minColWidth: CGFloat = 64

        let intrinsic: [CGFloat] = (0..<columnCount).map { col in
            var maxChars = 0
            if col < headers.count {
                maxChars = max(maxChars, String(headers[col].characters).count)
            }
            for row in rows where col < row.count {
                maxChars = max(maxChars, String(row[col].characters).count)
            }
            let raw = CGFloat(max(maxChars, 1)) * charWidth + horizontalPadding
            return max(raw, minColWidth)
        }

        let dividersWidth = CGFloat(max(0, columnCount - 1)) * 1.0
        let totalIntrinsic = intrinsic.reduce(0, +) + dividersWidth

        // If card has more room than intrinsic text, stretch columns to fill 100% of the card width!
        if availableWidth > totalIntrinsic {
            let extra = availableWidth - totalIntrinsic
            let perColumnAdd = extra / CGFloat(columnCount)
            return intrinsic.map { $0 + perColumnAdd }
        }

        return intrinsic
    }

    private func pad(_ cells: [AttributedString], to count: Int) -> [AttributedString] {
        if cells.count >= count { return Array(cells.prefix(count)) }
        return cells + Array(repeating: AttributedString(""), count: count - cells.count)
    }

    private func textAlignment(
        _ alignments: [AgentMarkdownColumnAlignment],
        index: Int
    ) -> TextAlignment {
        switch alignments[safe: index] ?? .leading {
        case .left, .leading: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }

    private func frameAlignment(
        _ alignments: [AgentMarkdownColumnAlignment],
        index: Int
    ) -> Alignment {
        switch alignments[safe: index] ?? .leading {
        case .left, .leading: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
