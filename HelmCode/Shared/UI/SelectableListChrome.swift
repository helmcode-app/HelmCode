//
//  SelectableListChrome.swift
//  HelmCode
//
//  Shared list-row chrome for plain selectable sheets (models, chats, …).
//

import SwiftUI

/// Title + monospaced wire id — used in Model picker and Project Settings Models.
struct AgentModelIdentityLabel: View {
    let title: String
    let wireID: String
    var titleWeight: Font.Weight = .regular

    init(model: AgentModelOption, titleWeight: Font.Weight = .regular) {
        self.title = model.title
        self.wireID = model.wireID
        self.titleWeight = titleWeight
    }

    init(title: String, wireID: String, titleWeight: Font.Weight = .regular) {
        self.title = title
        self.wireID = wireID
        self.titleWeight = titleWeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(titleWeight))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Text(wireID)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
        }
    }
}

/// Trailing selection checkmark that keeps layout stable when unselected.
struct SelectableListCheckmark: View {
    let selected: Bool

    var body: some View {
        Image(systemName: "checkmark")
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .opacity(selected ? 1 : 0)
            .accessibilityHidden(!selected)
    }
}

/// Plain list button row with optional trailing checkmark (vertical center).
struct SelectableListRow<Leading: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .leading)
                SelectableListCheckmark(selected: selected)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
