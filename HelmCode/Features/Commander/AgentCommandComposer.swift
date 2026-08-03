//
//  AgentCommandComposer.swift
//  HelmCode
//
//  Floating glass composer: branch · prompt · mode/model · send.
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

    private var composerDisabled: Bool {
        agent.phase.isBusy || !agent.socketState.isReady
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

            promptEditor
                .padding(.horizontal, 4)

            bottomBar
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        .helmSystemGlassPanel(cornerRadius: 26, interactive: true)
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
        chipMenu(
            title: branchMenuTitle,
            systemImage: "arrow.triangle.branch"
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

    // MARK: - Prompt

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $agent.prompt, selection: $promptSelection)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 64, maxHeight: 120)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .focused(promptFocused)
                .disabled(composerDisabled)

            if agent.prompt.isEmpty {
                Text(agent.composerMode.promptPlaceholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Bottom (mode · model · send)

    private var bottomBar: some View {
        HStack(spacing: 4) {
            chipMenu(
                title: agent.composerMode.title,
                systemImage: agent.composerMode.systemImage
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

            chipMenu(
                title: AgentModelOption.title(for: agent.modelID),
                systemImage: "cpu"
            ) {
                ForEach(AgentModelOption.catalog) { model in
                    Button {
                        agent.modelID = model.id
                    } label: {
                        if model.id == agent.modelID {
                            Label(model.title, systemImage: "checkmark")
                        } else {
                            VStack(alignment: .leading) {
                                Text(model.title)
                                Text(model.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .accessibilityLabel("Model \(AgentModelOption.title(for: agent.modelID))")

            Spacer(minLength: 4)

            sendButton
        }
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
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityLabel("Send")
        .animation(.easeInOut(duration: 0.15), value: canLaunch)
    }

    // MARK: - Shared chip menu

    private func chipMenu<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            Label {
                HStack(spacing: 3) {
                    Text(title)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .controlSize(.small)
        .disabled(composerDisabled)
    }

    // MARK: - Branch helpers

    private var branchMenuTitle: String {
        let b = agent.baseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        return b.isEmpty ? "branch" : b
    }

    private var branchChoices: [String] {
        var set: [String] = []
        func add(_ raw: String?) {
            guard let raw else { return }
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !set.contains(t) else { return }
            set.append(t)
        }
        add(agent.baseBranch)
        add(session.selectedProject?.trimmedBranch)
        add(session.sourceControl?.branch)
        add("main")
        add("master")
        add("develop")
        return set
    }

    // MARK: - File tags

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
}

// MARK: - Processing banner

struct AgentProcessingBanner: View {
    @ObservedObject var agent: AgentNetworkEngine

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(agent.composerMode == .agent ? "Agent running…" : "\(agent.composerMode.title)…")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            if let branch = agent.branch {
                Text(branch)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .helmSystemGlassPanel(cornerRadius: 16, interactive: false)
    }
}
