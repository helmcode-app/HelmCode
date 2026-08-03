//
//  AgentCommandPanel.swift
//  HelmCode
//
//  Project-scoped agent command drawer: prompt + contextPaths + Launch.
//  Bound to the open project's runner (same URL as VFS/HTTP). Unavailable without a project.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AgentCommandPanel: View {
    @ObservedObject var agent: AgentNetworkEngine
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var httpEngine: HelmCodeNetworkEngine

    @FocusState private var promptFocused: Bool
    @State private var isLaunching = false
    /// Cursor / selection inside the prompt editor (for inserting file tags).
    @State private var promptSelection: TextSelection?

    /// Agent is only meaningful while a project with a runner URL is open.
    private var projectRunnerReady: Bool {
        session.selectedProject?.normalizedRunnerURL != nil
    }

    private var composerDisabled: Bool {
        agent.phase.isBusy || !agent.socketState.isReady
    }

    private var canAddSelectedFile: Bool {
        guard !composerDisabled,
              let file = session.selectedFile,
              !file.isDirectory else { return false }
        return true
    }

    var body: some View {
        Group {
            if projectRunnerReady {
                activeWorkspaceBody
            } else {
                unavailableBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: session.selectedProjectID) { _, _ in
            seedBranchFromProject()
            agent.clearContextPaths()
        }
        .onChange(of: session.selectedFileID) { _, _ in
            seedBranchFromProject()
        }
    }

    // MARK: - No project

    private var unavailableBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Agent Command")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("UNAVAILABLE")
                    .font(.caption2.weight(.bold))
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground).opacity(0.55))

            Divider().opacity(0.5)

            VStack(spacing: 14) {
                Spacer(minLength: 24)
                Image(systemName: "bolt.horizontal.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Open a project to use the agent")
                    .font(.headline)
                Text(
                    """
                    The headless agent uses the same runner as the open project \
                    (HTTP + VFS + `ws://…/v1/agent`). There is no separate Agent backend.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Project open

    /// Timeline fills the column; composer **floats** over it so system glass can
    /// sample live content (same model as sidebar glass over the detail column).
    private var activeWorkspaceBody: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                headerBar
                AgentTimelineView(agent: agent, bottomClearance: 168)
            }

            VStack(spacing: 8) {
                if agent.phase.isProcessingLayout {
                    processingBanner
                        .padding(.horizontal, 12)
                }
                commandComposer
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .onAppear {
            seedBranchFromProject()
        }
    }

    // MARK: - Header

    /// Title + task phase only. Runner link health is the shared VFS status (sidebar).
    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Agent Command")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            phaseChip
            if agent.phase.isBusy {
                Button {
                    Task { await agent.cancelActiveTask() }
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel agent")
            } else if agent.result != nil || !agent.eventLog.isEmpty {
                Button {
                    agent.resetSession()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear timeline")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground).opacity(0.55))
    }

    private var phaseChip: some View {
        Text(agent.phase.label.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(phaseColor.opacity(0.16), in: Capsule())
            .foregroundStyle(phaseColor)
    }

    private var phaseColor: Color {
        switch agent.phase {
        case .idle, .ready: return .secondary
        case .connecting: return .orange
        case .launching, .processing: return .accentColor
        case .succeeded: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    // MARK: - Composer (stock system Liquid Glass only)

    /// Layout:
    /// ```
    /// [ branch ……………… Add file ]
    /// [ prompt with @file tags at cursor   ]
    /// [ mode · model …………… send ]
    /// ```
    private var commandComposer: some View {
        VStack(alignment: .leading, spacing: 0) {
            composerTopBar
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

            promptEditor
                .padding(.horizontal, 4)

            composerBottomBar
                .padding(.horizontal, 8)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        .helmSystemGlassPanel(cornerRadius: 26, interactive: true)
    }

    private var processingBanner: some View {
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

    // MARK: - Top bar (branch left · Add file right)

    private var composerTopBar: some View {
        HStack(spacing: 6) {
            branchMenu
            Spacer(minLength: 4)
            addFileButton
        }
    }

    private var branchMenu: some View {
        composerChipMenu(
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
                .focused($promptFocused)
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

    // MARK: - Bottom bar (mode · model · send)

    private var composerBottomBar: some View {
        HStack(spacing: 4) {
            composerChipMenu(
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

            composerChipMenu(
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

    private func composerChipMenu<Content: View>(
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

    private var sendButton: some View {
        Button {
            Task { await launch() }
        } label: {
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

    // MARK: - File tags in prompt

    /// Insert `@path` at the caret (or replace the current selection); also records contextPaths.
    private func insertSelectedFileTag() {
        guard let file = session.selectedFile, !file.isDirectory else { return }
        let path = VFSPath.normalize(file.path)
        guard !path.isEmpty else { return }

        agent.addContextPath(path)
        insertTextAtSelection(AgentPromptTagging.fileTag(for: path))
        promptFocused = true
    }

    private func insertTextAtSelection(_ insertion: String) {
        var text = agent.prompt
        let end = text.endIndex

        // Resolve insertion range from selection (or append).
        let replaceRange: Range<String.Index>
        if let selection = promptSelection {
            switch selection.indices {
            case .selection(let range):
                replaceRange = range
            case .multiSelection(let ranges):
                if let first = ranges.ranges.first {
                    replaceRange = first
                } else {
                    replaceRange = end..<end
                }
            }
        } else {
            replaceRange = end..<end
        }

        // Keep tags space-delimited for readability.
        var piece = insertion
        if replaceRange.lowerBound > text.startIndex {
            let before = text[text.index(before: replaceRange.lowerBound)]
            if !before.isWhitespace {
                piece = " " + piece
            }
        }
        if replaceRange.upperBound < text.endIndex {
            let after = text[replaceRange.upperBound]
            if !after.isWhitespace {
                piece += " "
            }
        } else if replaceRange.lowerBound == text.endIndex, !text.isEmpty {
            let last = text[text.index(before: text.endIndex)]
            if !last.isWhitespace, !piece.hasPrefix(" ") {
                piece = " " + piece
            }
        }

        text.replaceSubrange(replaceRange, with: piece)
        agent.prompt = text

        // Place caret after the inserted tag.
        if let newEnd = agent.prompt.index(
            replaceRange.lowerBound,
            offsetBy: piece.count,
            limitedBy: agent.prompt.endIndex
        ) {
            promptSelection = TextSelection(insertionPoint: newEnd)
        } else {
            promptSelection = TextSelection(insertionPoint: agent.prompt.endIndex)
        }
    }

    /// Pull `@path` tokens from the prompt into contextPaths before send.
    private func syncContextPathsFromPromptTags() {
        for path in AgentPromptTagging.paths(in: agent.prompt) {
            agent.addContextPath(path)
        }
    }

    // MARK: - Launch

    private var canLaunch: Bool {
        let trimmed = agent.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return projectRunnerReady
            && !trimmed.isEmpty
            && !agent.phase.isBusy
            && !isLaunching
            && agent.socketState.isReady
            && httpEngine.connectionState.isOnline
    }

    private func launch() async {
        isLaunching = true
        defer { isLaunching = false }
        seedBranchFromProject()
        syncContextPathsFromPromptTags()
        do {
            _ = try await agent.launchHeadlessAgent()
            promptFocused = false
        } catch {
            // phase / lastError already set on the engine
        }
    }

    private func seedBranchFromProject() {
        if agent.baseBranch == "main" || agent.baseBranch.isEmpty,
           let branch = session.selectedProject?.trimmedBranch,
           !branch.isEmpty {
            agent.baseBranch = branch
        }
    }
}

#Preview("No project") {
    AgentCommandPanel(
        agent: AgentNetworkEngine(),
        session: WorkspaceSession(),
        httpEngine: HelmCodeNetworkEngine()
    )
    .frame(width: 380, height: 720)
}
