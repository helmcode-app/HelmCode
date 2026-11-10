//
//  AgentCommandComposer.swift
//  HelmCode
//
//  Floating glass composer: context · branch · usage · prompt · mode/model · send/stop.
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    @State private var modelPickerOpen = false

    private var composerDisabled: Bool {
        isRunning || !agent.socketState.isReady
    }

    private var isRunning: Bool {
        isLaunching || agent.phase.isBusy
    }

    private var promptPlaceholderText: String {
        if isRunning {
            return "Working on response…"
        }
        return agent.composerMode.promptPlaceholder
    }

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

                composerRule
                    .padding(.vertical, 8)

                AgentComposerPromptEditor(
                    text: $agent.prompt,
                    selection: $promptSelection,
                    placeholder: promptPlaceholderText,
                    isDisabled: composerDisabled,
                    canSend: canLaunch,
                    promptFocused: promptFocused,
                    onSend: onSend,
                    onInsertNewline: insertPromptNewline,
                    menuKeys: menuKeys
                )

                composerRule
                    .padding(.vertical, 8)

                bottomBar
            }
            .padding(AgentChrome.composerInset)
            .helmSystemGlassPanel(cornerRadius: AgentChrome.composerRadius, interactive: true)
        }
        .sheet(isPresented: $modelPickerOpen) {
            AgentModelPickerSheet(agent: agent, isPresented: $modelPickerOpen)
        }
    }

    private var composerRule: some View {
        Rectangle()
            .fill(AgentChrome.hairline(colorScheme))
            .frame(height: 1 / max(displayScale, 1))
            .accessibilityHidden(true)
    }

    // MARK: - Top (context · branch · usage)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !contextChips.isEmpty {
                contextPillsRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 6) {
                branchLabel
                    .frame(maxWidth: .infinity, alignment: .leading)
                AgentComposerUsageMeter(usage: agent.sessionUsage)
                    .layoutPriority(1)
            }
        }
        .animation(AgentChrome.chipSpring, value: contextChips.map(\.id))
    }

    private var contextChips: [ContextChip] {
        var chips: [ContextChip] = agent.contextPaths.map {
            ContextChip(id: $0, path: $0, kind: .pinned)
        }
        if let selected = session.selectedFile, !selected.isDirectory {
            let path = VFSPath.normalize(selected.path)
            if !path.isEmpty,
               !chips.contains(where: { VFSPath.matches($0.path, path) }) {
                chips.insert(ContextChip(id: "active:\(path)", path: path, kind: .activeFile), at: 0)
            }
        }
        return chips
    }

    private var contextPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(contextChips) { chip in
                    contextPill(chip)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Context files")
    }

    @ViewBuilder
    private func contextPill(_ chip: ContextChip) -> some View {
        switch chip.kind {
        case .pinned:
            HStack(spacing: 5) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9, weight: .bold))
                Text(AgentChatFormatting.shortDisplayPath(chip.path))
                    .font(.caption2.weight(.semibold).monospaced())
                    .lineLimit(1)
                Button {
                    withAnimation(AgentChrome.chipSpring) {
                        removeContext(chip.path)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(chip.path)")
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .frame(height: 24)
            .background(
                Color.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: AgentChrome.chipRadius, style: .continuous)
            )
            .foregroundStyle(Color.accentColor)

        case .activeFile:
            Button {
                withAnimation(AgentChrome.chipSpring) {
                    agent.addContextPath(chip.path)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text(AgentChatFormatting.shortDisplayPath(chip.path))
                        .font(.caption2.weight(.semibold).monospaced())
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(
                    Color(.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: AgentChrome.chipRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AgentChrome.chipRadius, style: .continuous)
                        .strokeBorder(AgentChrome.hairline(colorScheme), lineWidth: 1)
                )
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add \(chip.path) to context")
            .disabled(composerDisabled)
        }
    }

    private func removeContext(_ path: String) {
        agent.removeContextPath(path)
        let tag = AgentPromptTagging.fileTag(for: path)
        if agent.prompt.contains(tag) {
            agent.prompt = agent.prompt
                .replacingOccurrences(of: tag + " ", with: "")
                .replacingOccurrences(of: tag, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var branchLabel: some View {
        Label(currentBranchTitle, systemImage: "arrow.triangle.branch")
            .font(.caption.weight(.semibold).monospaced())
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

    // MARK: - Bottom (mode · model · send/stop)

    private var bottomBar: some View {
        HStack(spacing: 4) {
            modeMenu
            modelChip
            Spacer(minLength: 4)
            sendOrStopButton
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

    private var sendOrStopButton: some View {
        Button {
            if isRunning {
                Task { await agent.cancelActiveTask() }
            } else {
                onSend()
            }
        } label: {
            Image(systemName: isRunning ? "stop.fill" : "arrow.up")
                .font(.body.weight(.bold))
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: AgentChrome.sendStopSize, height: AgentChrome.sendStopSize)
        .buttonStyle(.glassProminent)
        .tint(isRunning ? .red : Color.accentColor)
        .disabled(!isRunning && !canLaunch)
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel(isRunning ? "Stop" : "Send")
        .help(isRunning ? "Stop the current agent turn" : "Return to send · Option+Return for newline")
        .animation(AgentChrome.sendMorph, value: isRunning)
        .animation(AgentChrome.sendMorph, value: canLaunch)
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

// MARK: - Context chip model

private struct ContextChip: Identifiable {
    enum Kind {
        case pinned
        case activeFile
    }

    let id: String
    let path: String
    let kind: Kind
}
