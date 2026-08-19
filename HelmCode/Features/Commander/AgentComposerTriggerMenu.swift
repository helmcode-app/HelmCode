//
//  AgentComposerTriggerMenu.swift
//  HelmCode
//
//  In-chat popup for `/` skills and `@` files (not a system picker).
//

import SwiftUI

struct AgentComposerTriggerMenu: View {
    let kind: AgentComposerTriggerKind
    let sections: [AgentComposerTriggerSection]
    let highlightedID: AgentComposerTriggerItem.ID?
    var onSelect: (AgentComposerTriggerItem) -> Void
    var onHighlight: (AgentComposerTriggerItem.ID) -> Void

    private var items: [AgentComposerTriggerItem] {
        AgentComposerTriggerCatalog.flattened(sections)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.35)
            list
            Divider().opacity(0.35)
            footer
        }
        .helmSystemGlassPanel(cornerRadius: 18, interactive: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(kind.menuTitle)
    }

    private var header: some View {
        Text(kind.menuTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if items.isEmpty {
            Text(kind.emptyCopy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 18)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sections) { section in
                            if let header = section.header, !section.items.isEmpty {
                                Text(header)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }
                            ForEach(section.items) { item in
                                row(item)
                                    .id(item.id)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                }
                .frame(maxHeight: 240)
                .scrollDismissesKeyboard(.never)
                .onChange(of: highlightedID) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ item: AgentComposerTriggerItem) -> some View {
        let highlighted = item.id == highlightedID
        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: 10) {
                leadingIcon(item, highlighted: highlighted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.subheadline.weight(highlighted ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(highlighted ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering in
            if hovering { onHighlight(item.id) }
        }
        .accessibilityLabel(item.title)
        .accessibilityValue(item.subtitle)
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    @ViewBuilder
    private func leadingIcon(_ item: AgentComposerTriggerItem, highlighted: Bool) -> some View {
        switch item {
        case .file(let node):
            FileTypeIcon(
                node: node,
                isSelected: highlighted,
                size: FileTypeIconMetrics.compact
            )
        default:
            Image(systemName: item.systemImage ?? "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                .frame(width: FileTypeIconMetrics.compact, height: FileTypeIconMetrics.compact)
        }
    }

    private var footer: some View {
        Text("↑↓ to choose · Return to insert · Esc to close")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }
}
