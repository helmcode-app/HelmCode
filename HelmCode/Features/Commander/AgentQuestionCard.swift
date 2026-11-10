//
//  AgentQuestionCard.swift
//  HelmCode
//
//  Interactive card for LLM `ask_user_question` tool invocations (Pi harness style).
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentQuestionCard: View {
    let question: AgentUserQuestion
    var onSelectOption: ((String) -> Void)? = nil
    var onSubmitAnswer: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedOptionIDs: Set<String> = []
    @State private var expandedPreviewID: String? = nil
    @State private var isSubmitted: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            AgentAccentRail(tint: .accentColor, width: 2.5)

            VStack(alignment: .leading, spacing: 10) {
                header
                questionText
                optionsList
                footerActions
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            AgentChrome.codeFill,
            in: RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AgentChrome.cardRadius, style: .continuous)
                .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tint)

            Text(question.header ?? "QUESTION")
                .font(.caption2.weight(.bold).monospaced())
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if question.multiSelect {
                Text("· Multi-select")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if isSubmitted {
                Label("Answered", systemImage: "checkmark")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Question text

    private var questionText: some View {
        Text(question.question)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    // MARK: - Options

    private var optionsList: some View {
        VStack(spacing: 6) {
            ForEach(question.options) { option in
                optionRow(option)
            }
        }
    }

    private func optionRow(_ option: AgentQuestionOption) -> some View {
        let isSelected = selectedOptionIDs.contains(option.id)
        let hasPreview = option.preview != nil && !(option.preview!.isEmpty)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                toggleSelection(for: option)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(
                        systemName: question.multiSelect
                            ? (isSelected ? "checkmark.square.fill" : "square")
                            : (isSelected ? "checkmark.circle.fill" : "circle")
                    )
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.label)
                            .font(.footnote.weight(isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.88))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let desc = option.description, !desc.isEmpty {
                            Text(desc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if hasPreview {
                        Button {
                            withAnimation(AgentChrome.chipSpring) {
                                if expandedPreviewID == option.id {
                                    expandedPreviewID = nil
                                } else {
                                    expandedPreviewID = option.id
                                }
                            }
                        } label: {
                            Image(systemName: expandedPreviewID == option.id ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Toggle option preview")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.12)
                        : Color(.secondarySystemFill).opacity(0.35),
                    in: RoundedRectangle(cornerRadius: AgentChrome.chipRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChrome.chipRadius, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.4) : AgentChrome.hairline(colorScheme),
                            lineWidth: 1
                        )
                )
            }
            .buttonStyle(.plain)

            if hasPreview, expandedPreviewID == option.id, let preview = option.preview {
                previewBox(preview)
                    .padding(.leading, 26)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func previewBox(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Color(.tertiarySystemFill).opacity(0.6),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private var footerActions: some View {
        let hasSelection = !selectedOptionIDs.isEmpty
        let answerText = formattedAnswer()

        return HStack(spacing: 8) {
            Button {
                guard hasSelection else { return }
                isSubmitted = true
                onSubmitAnswer?(answerText)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paperplane.fill")
                        .font(.caption2)
                    Text(isSubmitted ? "Submitted" : "Submit Answer")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(hasSelection ? Color.white : Color.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    hasSelection ? Color.accentColor : Color(.secondarySystemFill),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection || isSubmitted)

            Button {
                guard hasSelection else { return }
                onSelectOption?(answerText)
            } label: {
                Label("Fill Composer", systemImage: "pencil.line")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)

            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - Helpers

    private func toggleSelection(for option: AgentQuestionOption) {
        withAnimation(AgentChrome.chipSpring) {
            if question.multiSelect {
                if selectedOptionIDs.contains(option.id) {
                    selectedOptionIDs.remove(option.id)
                } else {
                    selectedOptionIDs.insert(option.id)
                }
            } else {
                selectedOptionIDs = [option.id]
            }
        }
    }

    private func formattedAnswer() -> String {
        let chosen = question.options.filter { selectedOptionIDs.contains($0.id) }
        let labels = chosen.map(\.label).joined(separator: ", ")
        if let header = question.header, !header.isEmpty {
            return "\(header): \(labels)"
        }
        return labels
    }
}
