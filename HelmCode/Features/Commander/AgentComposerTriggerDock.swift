//
//  AgentComposerTriggerDock.swift
//  HelmCode
//
//  Hosts the `/` / `@` picker above the composer glass and routes editor keys.
//

import SwiftUI

struct AgentComposerTriggerDock<Composer: View>: View {
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession
    @Binding var promptSelection: TextSelection?
    var promptFocused: FocusState<Bool>.Binding
    var composerDisabled: Bool
    @ViewBuilder var composer: (_ menuKeys: AgentComposerMenuKeys) -> Composer

    @State private var suppressMenu = false
    @State private var highlightedItemID: AgentComposerTriggerItem.ID?

    /// Token at the caret, ignoring menu dismissal (Esc).
    private var rawTrigger: AgentComposerTrigger? {
        guard !composerDisabled else { return nil }
        return AgentComposerTrigger.detect(in: agent.prompt, selection: promptSelection)
    }

    private var trigger: AgentComposerTrigger? {
        guard !suppressMenu else { return nil }
        return rawTrigger
    }

    private var sections: [AgentComposerTriggerSection] {
        guard let trigger else { return [] }
        return AgentComposerTriggerCatalog.sections(
            trigger: trigger,
            project: session.selectedProject,
            selectedFileID: session.selectedFileID,
            modes: agent.availableComposerModes
        )
    }

    private var items: [AgentComposerTriggerItem] {
        AgentComposerTriggerCatalog.flattened(sections)
    }

    private var itemIDs: [AgentComposerTriggerItem.ID] {
        items.map(\.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trigger {
                AgentComposerTriggerMenu(
                    kind: trigger.kind,
                    sections: sections,
                    highlightedID: highlightedItemID,
                    onSelect: confirm,
                    onHighlight: { highlightedItemID = $0 }
                )
            }
            composer(
                AgentComposerMenuKeys(
                    isActive: trigger != nil,
                    onMove: moveHighlight,
                    onConfirm: confirmHighlighted,
                    onCancel: { suppressMenu = true }
                )
            )
        }
        .onChange(of: rawTrigger?.menuIdentity) { _, identity in
            // Esc closes the menu for this token; leaving the token (or deleting `/` `@`)
            // clears suppression so the next trigger can open it again.
            if identity == nil {
                suppressMenu = false
            }
        }
        .onChange(of: trigger?.menuIdentity) { _, _ in
            highlightedItemID = items.first?.id
        }
        .onChange(of: itemIDs) { _, ids in
            if let highlightedItemID, ids.contains(highlightedItemID) { return }
            highlightedItemID = ids.first
        }
    }

    private func moveHighlight(_ delta: Int) {
        guard !items.isEmpty else { return }
        let current = items.firstIndex(where: { $0.id == highlightedItemID }) ?? 0
        let next = (current + delta + items.count) % items.count
        highlightedItemID = items[next].id
    }

    @discardableResult
    private func confirmHighlighted() -> Bool {
        guard let highlightedItemID,
              let item = items.first(where: { $0.id == highlightedItemID })
        else { return false }
        confirm(item)
        return true
    }

    private func confirm(_ item: AgentComposerTriggerItem) {
        guard let trigger = AgentComposerTrigger.detect(
            in: agent.prompt,
            selection: promptSelection
        ), let range = trigger.range(in: agent.prompt) else { return }

        let replacement = item.commit(into: agent)
        let edited = AgentPromptEditing.replace(
            range,
            with: replacement,
            in: agent.prompt
        )
        agent.prompt = edited.text
        promptSelection = edited.selection
        suppressMenu = true
        promptFocused.wrappedValue = true
    }
}
