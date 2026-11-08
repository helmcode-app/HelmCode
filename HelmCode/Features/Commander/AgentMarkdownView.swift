//
//  AgentMarkdownView.swift
//  HelmCode
//
//  Lightweight Markdown for agent answers: prose + industrial fenced code blocks.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentMarkdownView: View {
    let source: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedBlockID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.blocks(from: source).enumerated()), id: \.offset) { index, block in
                switch block {
                case .prose(let text):
                    proseView(text)
                case .code(let language, let code):
                    codeBlock(id: index, language: language, code: code)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func proseView(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            Text(Self.attributedProse(trimmed))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func codeBlock(id: Int, language: String?, code: String) -> some View {
        let lang = (language?.isEmpty == false) ? language! : "code"
        let justCopied = copiedBlockID == id

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
                    Spacer(minLength: 4)
                    Button {
                        #if canImport(UIKit)
                        UIPasteboard.general.string = code
                        #endif
                        withAnimation(AgentChrome.sendMorph) {
                            copiedBlockID = id
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1200))
                            if copiedBlockID == id {
                                withAnimation(AgentChrome.sendMorph) {
                                    copiedBlockID = nil
                                }
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
                    .accessibilityLabel(justCopied ? "Copied" : "Copy code")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                Rectangle()
                    .fill(AgentChrome.hairline(colorScheme))
                    .frame(height: 1)
                    .accessibilityHidden(true)

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code.isEmpty ? " " : code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
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

    // MARK: - Parsing

    private enum Block {
        case prose(String)
        case code(language: String?, code: String)
    }

    private static func blocks(from source: String) -> [Block] {
        var result: [Block] = []
        var proseBuffer = ""
        var inFence = false
        var fenceLanguage: String?
        var codeBuffer = ""

        func flushProse() {
            if !proseBuffer.isEmpty {
                result.append(.prose(proseBuffer))
                proseBuffer = ""
            }
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let raw = String(line)
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence {
                    result.append(.code(language: fenceLanguage, code: String(codeBuffer.dropLast(codeBuffer.hasSuffix("\n") ? 1 : 0))))
                    codeBuffer = ""
                    fenceLanguage = nil
                    inFence = false
                } else {
                    flushProse()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                    fenceLanguage = lang.isEmpty ? nil : lang
                    inFence = true
                }
                continue
            }
            if inFence {
                codeBuffer.append(raw)
                codeBuffer.append("\n")
            } else {
                proseBuffer.append(raw)
                proseBuffer.append("\n")
            }
        }

        if inFence {
            result.append(.code(language: fenceLanguage, code: String(codeBuffer.dropLast(codeBuffer.hasSuffix("\n") ? 1 : 0))))
        } else {
            flushProse()
        }

        if result.isEmpty {
            return [.prose(source)]
        }
        return result
    }

    private static func attributedProse(_ text: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }
}
