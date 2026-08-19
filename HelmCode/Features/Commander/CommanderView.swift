//
//  CommanderView.swift
//  HelmCode
//
//  AI agent chat — hosted in the system `.inspector` column.
//
//  File map:
//    CommanderView.swift                 — inspector wrapper
//    AgentCommandPanel.swift             — header + timeline + composer dock
//    AgentCommandHeader.swift            — session title / picker
//    AgentCommandComposer.swift          — glass chrome (branch · usage · send)
//    AgentComposerTriggerDock.swift      — `/` skills · `@` files host
//    AgentComposerTrigger.swift          — caret token detect
//    AgentComposerTriggerItems.swift     — catalog + pick commit
//    AgentComposerTriggerMenu.swift      — in-chat popup
//    AgentComposerPromptEditor.swift     — TextEditor + Return / picker keys
//    AgentComposerChipMenu.swift         — mode / model chips
//    AgentComposerBranches.swift         — live branch label
//    AgentModelPickerSheet.swift         — model · think · fast
//    AgentPromptEditing.swift            — caret insert / replace
//    AgentPromptTagging.swift            — `@path` → contextPaths
//    AgentTimelineView.swift             — EventLog scroll
//    AgentTranscriptItem.swift           — group EventLog → turns
//    AgentTurnContent.swift              — thought / tools / answer
//    AgentTurnCard.swift / AgentUserBubble / AgentToolRow
//    AgentProcessingBanner.swift         — working strip
//    AgentChatFormatting.swift           — duration / path helpers
//    AgentSessionPicker.swift            — chat list sheet
//

import SwiftUI

struct CommanderView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession

    var body: some View {
        AgentCommandPanel(
            agent: agent,
            session: session,
            httpEngine: engine
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
