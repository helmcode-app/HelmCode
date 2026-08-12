//
//  AgentCommandComposer.swift
//  HelmCode
//
//  Floating glass composer: branch · prompt · mode/model · send.
//  Pieces: AgentComposerChipMenu, AgentComposerPromptEditor, AgentModelPickerSheet.
//

import SwiftUI

struct AgentCommandComposer: View {
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession

    var promptFocused: FocusState<Bool>.Binding
    @Binding var promptSelection: TextSelection?
    @Binding var isLaunching: Bool

    var canLaunch: Bool
    var canAddSelectedFile: Bool
    var onSend: () -> Void

    @State private var modelPickerOpen = false

    private var composerDisabled: Bool {
        agent.phase.isBusy || !agent.socketState.isReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

            AgentComposerPromptEditor(
                text: $agent.prompt,
                selection: $promptSelection,
                placeholder: agent.composerMode.promptPlaceholder,
                isDisabled: composerDisabled,
                canSend: canLaunch,
                promptFocused: promptFocused,
                onSend: onSend,
                onInsertNewline: insertPromptNewline
            )
            .padding(.horizontal, 4)

            bottomBar
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        .helmSystemGlassPanel(cornerRadius: 26, interactive: true)
        .sheet(isPresented: $modelPickerOpen) {
            AgentModelPickerSheet(agent: agent, isPresented: $modelPickerOpen)
        }
    }

    // MARK: - Top (branch · add file)

    private var topBar: some View {
        HStack(spacing: 6) {
            branchMenu
            Spacer(minLength: 4)
            addFileButton
        }
    }

    private var branchMenu: some View {
        AgentComposerChipMenu(
            title: AgentComposerBranches.displayTitle(agent.baseBranch),
            systemImage: "arrow.triangle.branch",
            disabled: composerDisabled
        ) {
            ForEach(branchChoices, id: \.self) { branch in
                Button {
                    agent.baseBranch = branch
                } label: {
                    if branch == agent.baseBranch {
                        Label(branch, systemImage: "checkmark")
                    } else {
                        Text(branch)
                    }
                }
            }
        }
        .accessibilityLabel("Branch \(agent.baseBranch)")
    }

    private var addFileButton: some View {
        Button {
            insertSelectedFileTag()
        } label: {
            Label("Add file", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(!canAddSelectedFile)
        .accessibilityLabel("Add selected file at cursor")
        .help(
            canAddSelectedFile
                ? "Insert @\(session.selectedFile?.path ?? "file") at the caret"
                : "Select a file in the project tree first"
        )
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
            ForEach(AgentComposerMode.allCases) { mode in
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

    // MARK: - Branch / tags

    private var branchChoices: [String] {
        AgentComposerBranches.choices(
            current: agent.baseBranch,
            projectBranch: session.selectedProject?.trimmedBranch,
            sourceControlBranch: session.sourceControl?.branch
        )
    }

    private func insertSelectedFileTag() {
        guard let file = session.selectedFile, !file.isDirectory else { return }
        let path = VFSPath.normalize(file.path)
        guard !path.isEmpty else { return }

        agent.addContextPath(path)
        let edited = AgentPromptEditing.insert(
            AgentPromptTagging.fileTag(for: path),
            into: agent.prompt,
            selection: promptSelection
        )
        agent.prompt = edited.text
        promptSelection = edited.selection
        promptFocused.wrappedValue = true
    }

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
