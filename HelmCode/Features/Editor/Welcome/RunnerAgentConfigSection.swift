//
//  RunnerAgentConfigSection.swift
//  HelmCode
//
//  Configure which ACP harness the runner should spawn (`/v1/agent`).
//

import SwiftUI

struct RunnerAgentConfigSection: View {
    var makeClient: () -> RunnerCoreAPIClient?
    var isParentBusy: Bool
    var onToast: (String) -> Void
    /// After a successful enable / switch, nudge the active agent link to re-probe.
    var onAgentBecameReady: () -> Void = {}

    @State private var view: AgentConfigView?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var draftEnabled = false
    @State private var draftHarness: AgentHarnessID = .claude
    @State private var draftProvider: AgentProviderID = .opencodeGo
    @State private var draftApiKey = ""
    @State private var localError: String?

    private var isBusy: Bool { isParentBusy || isSaving }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionCaption(title: "Agent Sessions")
                Spacer()
                if let view {
                    phasePill(view.phase)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if isLoading && view == nil {
                    loadingRow
                } else if let view {
                    content(view)
                } else {
                    emptyRow
                }
            }
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )

            if let localError {
                Text(localError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .task { await reload() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ remote: AgentConfigView) -> some View {
        enableRow
        Divider().padding(.leading, 16)
        harnessPicker(remote)
        if draftHarness.needsProvider {
            Divider().padding(.leading, 16)
            providerPicker
        }
        Divider().padding(.leading, 16)
        apiKeyRow(remote)
        if let error = remote.error, remote.phase == .error {
            Divider().padding(.leading, 16)
            errorRow(error)
        }
        Divider().padding(.leading, 16)
        applyRow(remote)
    }

    private var enableRow: some View {
        Toggle(isOn: $draftEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Enable ACP")
                    .font(.body.weight(.medium))
                Text("Spawn the selected harness on this runner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .disabled(isBusy)
    }

    private func harnessPicker(_ remote: AgentConfigView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Harness")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let ids = catalogIDs(remote)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(ids) { id in
                    harnessChip(id)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func harnessChip(_ id: AgentHarnessID) -> some View {
        let selected = draftHarness == id
        return Button {
            draftHarness = id
            if !id.needsProvider {
                // keep provider for when user switches back to OpenCode
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: id.systemImage)
                    .font(.caption.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(id.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(id.subtitle)
                        .font(.caption2)
                        .foregroundStyle(selected ? Color.accentColor.opacity(0.85) : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : .clear, lineWidth: 1)
            )
            .foregroundStyle(selected ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var providerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker("Provider", selection: $draftProvider) {
                ForEach(AgentProviderID.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func apiKeyRow(_ remote: AgentConfigView) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if remote.hasApiKey, draftApiKey.isEmpty {
                    Text(remote.apiKeyHint ?? "Saved on runner")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }
            }

            SecureField(apiKeyPlaceholder(for: draftHarness), text: $draftApiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color(.tertiarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .disabled(isBusy)

            Text("Stored on the runner only. Leave blank to keep the current key.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("ACP stays off until you tap Update. First install can take a minute or two — keep this sheet open.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func applyRow(_ remote: AgentConfigView) -> some View {
        HStack(spacing: 12) {
            if draftEnabled != remote.enabled
                || draftHarness != (remote.harness ?? draftHarness)
                || (draftHarness.needsProvider && draftProvider != (remote.provider ?? draftProvider))
                || !draftApiKey.isEmpty
            {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if remote.enabled, remote.phase == .ready {
                Label("Running", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }

            Spacer(minLength: 0)

            Button {
                Task { await apply() }
            } label: {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(draftEnabled ? "Installing…" : "Saving…")
                    }
                } else {
                    Text(applyButtonTitle)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !canApply)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var loadingRow: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading agent configuration…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var emptyRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
            Text("Couldn’t load agent configuration.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Retry") {
                Task { await reload() }
            }
            .font(.caption.weight(.semibold))
            .disabled(isBusy)
        }
        .padding(16)
    }

    private func phasePill(_ phase: AgentRuntimePhase) -> some View {
        let color: Color = {
            switch phase {
            case .ready: return .green
            case .starting: return .orange
            case .error: return .red
            case .stopped: return .orange
            case .disabled: return .secondary
            }
        }()
        return Text(phase.displayName.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.55)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: - Logic

    private var applyButtonTitle: String {
        if !draftEnabled {
            return view?.enabled == true ? "Disable" : "Save"
        }
        if view?.enabled == true, view?.harness != draftHarness {
            return "Switch"
        }
        return view?.enabled == true ? "Update" : "Enable"
    }

    private var canApply: Bool {
        if draftEnabled, draftHarness.needsProvider {
            // provider always has a default
        }
        return true
    }

    private func catalogIDs(_ remote: AgentConfigView) -> [AgentHarnessID] {
        let fromRemote = remote.harnesses.map(\.id)
        return fromRemote.isEmpty ? AgentHarnessID.allCases : fromRemote
    }

    private func apiKeyPlaceholder(for harness: AgentHarnessID) -> String {
        switch harness {
        case .claude: return "ANTHROPIC_API_KEY"
        case .codex: return "CODEX_API_KEY / OPENAI_API_KEY"
        case .cursor: return "CURSOR_API_KEY"
        case .grok: return "XAI_API_KEY"
        case .opencode: return "Provider API key"
        }
    }

    private func adopt(_ remote: AgentConfigView) {
        view = remote
        draftEnabled = remote.enabled
        draftHarness = remote.harness ?? .claude
        draftProvider = remote.provider ?? .opencodeGo
        draftApiKey = ""
        localError = remote.phase == .error ? remote.error : nil
    }

    @MainActor
    private func reload() async {
        guard let client = makeClient() else {
            isLoading = false
            localError = "This iPad has no token for this runner."
            return
        }
        isLoading = view == nil
        defer { isLoading = false }
        do {
            let next = try await client.agentConfig()
            adopt(next)
            localError = next.phase == .error ? next.error : nil
        } catch {
            localError = RunnerAuthCopy.message(for: error)
        }
    }

    @MainActor
    private func apply() async {
        guard let client = makeClient() else {
            onToast("This iPad has no token for this runner.")
            return
        }
        isSaving = true
        localError = nil
        defer { isSaving = false }

        var body = AgentConfigUpdateBody(
            enabled: draftEnabled,
            harness: draftHarness
        )
        if draftHarness.needsProvider {
            body.provider = draftProvider
        }
        let trimmedKey = draftApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            body.apiKey = trimmedKey
        }

        do {
            let next = try await client.putAgentConfig(body)
            adopt(next)
            if next.phase == .error {
                localError = next.error ?? "Harness failed to start"
                onToast(localError ?? "Harness failed to start")
            } else if next.enabled, next.phase == .ready {
                onAgentBecameReady()
            }
        } catch {
            let message = RunnerAuthCopy.message(for: error)
            localError = message
            onToast(message)
        }
    }
}
