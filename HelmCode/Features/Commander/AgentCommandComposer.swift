//
//  AgentCommandComposer.swift
//  HelmCode
//
//  Floating glass composer: branch · usage · prompt · mode/model · send.
//  `/` and `@` picker: AgentComposerTriggerDock.
//

import SwiftUI

struct AgentCommandComposer: View {
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession

    var promptFocused: FocusState<Bool>.Binding
    @Binding var promptSelection: TextSelection?
    @Binding var isLaunching: Bool

    var canLaunch: Bool
    var onSend: () -> Void

    @State private var modelPickerOpen = false

    private var composerDisabled: Bool {
        agent.phase.isBusy || !agent.socketState.isReady
    }

    /// Inset from the glass rim to the four corner controls (branch, usage, mode, send).
    private static let chromeInset: CGFloat = 14

    var body: some View {
        AgentComposerTriggerDock(
            agent: agent,
            session: session,
            promptSelection: $promptSelection,
            promptFocused: promptFocused,
            composerDisabled: composerDisabled
        ) { menuKeys in
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.bottom, 2)

                AgentComposerPromptEditor(
                    text: $agent.prompt,
                    selection: $promptSelection,
                    placeholder: agent.composerMode.promptPlaceholder,
                    isDisabled: composerDisabled,
                    canSend: canLaunch,
                    promptFocused: promptFocused,
                    onSend: onSend,
                    onInsertNewline: insertPromptNewline,
                    menuKeys: menuKeys
                )

                bottomBar
                    .padding(.top, 2)
            }
            .padding(Self.chromeInset)
            .helmSystemGlassPanel(cornerRadius: 26, interactive: true)
        }
        .sheet(isPresented: $modelPickerOpen) {
            AgentModelPickerSheet(agent: agent, isPresented: $modelPickerOpen)
        }
    }

    // MARK: - Top (branch · usage)

    private var topBar: some View {
        HStack(spacing: 6) {
            branchLabel
            Spacer(minLength: 4)
            usageMeter
        }
    }

    private var branchLabel: some View {
        Label(currentBranchTitle, systemImage: "arrow.triangle.branch")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Branch \(currentBranchTitle)")
    }

    private var currentBranchTitle: String {
        AgentComposerBranches.currentName(
            sourceControlBranch: session.sourceControl?.branch,
            projectBranch: session.selectedProject?.trimmedBranch,
            fallback: agent.baseBranch
        )
    }

    private var usageMeter: some View {
        let usage = agent.sessionUsage
        return HStack(spacing: 8) {
            Text(usage?.contextLabel ?? "—")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(usageTint(usage?.fraction ?? 0))
            if let cost = usage?.costLabel {
                Text(cost)
                    .font(.caption.weight(.regular).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usageAccessibility(usage))
        .help(usageHelp(usage))
    }

    private func usageTint(_ fraction: Double) -> Color {
        if fraction >= 0.95 { return .red }
        if fraction >= 0.75 { return .orange }
        return .secondary
    }

    private func usageAccessibility(_ usage: SessionUsage?) -> String {
        guard let usage else { return "Context size unavailable" }
        var parts = ["Context \(usage.contextLabel)"]
        if let cost = usage.costLabel {
            parts.append("Cost \(cost)")
        }
        return parts.joined(separator: ", ")
    }

    private func usageHelp(_ usage: SessionUsage?) -> String {
        guard let usage else {
            return "Context window and cost appear when the agent reports usage"
        }
        if let cost = usage.costLabel {
            return "Context \(usage.contextLabel) · \(cost)"
        }
        return "Context \(usage.contextLabel)"
    }

    // MARK: - Bottom (mode · model · send)

    private var bottomBar: some View {
        HStack(spacing: 4) {
            modeMenu
            modelChip
            Spacer(minLength: 4)
            sendButton
        }
    }

    private var modeMenu: some View {
        AgentComposerChipMenu(
            title: agent.composerMode.title,
            systemImage: agent.composerMode.systemImage,
            disabled: composerDisabled
        ) {
            ForEach(agent.availableComposerModes) { mode in
                Button {
                    agent.composerMode = mode
                } label: {
                    if mode == agent.composerMode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Label(mode.title, systemImage: mode.systemImage)
                    }
                }
            }
        }
        .accessibilityLabel("Mode \(agent.composerMode.title)")
    }

    private var modelChip: some View {
        AgentComposerChipButton(
            title: AgentModelOption.title(for: agent.modelID, in: agent.modelCatalog),
            systemImage: "cpu",
            disabled: composerDisabled
        ) {
            modelPickerOpen = true
        }
        .accessibilityLabel(
            "Model \(AgentModelOption.title(for: agent.modelID, in: agent.modelCatalog))"
        )
    }

    private var sendButton: some View {
        Button(action: onSend) {
            if isLaunching || agent.phase.isProcessingLayout {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.up")
                    .font(.body.weight(.bold))
            }
        }
        .frame(width: 34, height: 34)
        .buttonStyle(.glassProminent)
        .disabled(!canLaunch)
        // Primary path is Return in the editor; keep ⌘↩ as a backup when focus is elsewhere.
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel("Send")
        .help("Return to send · Option+Return for newline")
        .animation(.easeInOut(duration: 0.15), value: canLaunch)
    }

    // MARK: - Newline

    private func insertPromptNewline() {
        let edited = AgentPromptEditing.insertRaw(
            "\n",
            into: agent.prompt,
            selection: promptSelection
        )
        agent.prompt = edited.text
        promptSelection = edited.selection
    }
}
