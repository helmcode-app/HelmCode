//
//  ModelsSettingsView.swift
//  HelmCode
//
//  Cursor-style model enablement for a runner host (Project Settings).
//  Available when that runner URL is reachable — does not require an open chat session.
//

import SwiftUI

struct ModelsSettingsView: View {
    /// Runner base URL used for catalog + prefs key (normalized on use).
    let baseURL: String
    let apiToken: String
    /// When the active agent targets the same host, keep its catalog in sync.
    var agent: AgentNetworkEngine?

    @State private var catalog: [AgentModelOption] = []
    @State private var enabledIDs: Set<String> = []
    @State private var hasCuration = false
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var loadError: String?

    private var normalizedURL: String {
        RunnerURL.normalizeHTTP(baseURL)
    }

    private var filteredCatalog: [AgentModelOption] {
        AgentModelOption.matching(catalog, query: searchText)
    }

    private var grouped: [(provider: String, models: [AgentModelOption])] {
        AgentModelOption.groupedByProvider(filteredCatalog)
    }

    private var enabledCount: Int {
        catalog.filter { enabledIDs.contains($0.id) }.count
    }

    private var selectedModelID: String {
        guard let agent, agentTargetsThisRunner else { return "" }
        return agent.modelID
    }

    private var agentTargetsThisRunner: Bool {
        guard let agent else { return false }
        let active = RunnerURL.normalizeHTTP(agent.baseURLString)
        return !active.isEmpty && active == normalizedURL
    }

    var body: some View {
        List {
            content
        }
        .searchable(text: $searchText, prompt: "Search models")
        .helmInlineNavigationTitle("Models")
        .toolbar { overflowMenu }
        .overlay {
            if isLoading, !catalog.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
        .task {
            loadFromPrefs()
            await refreshCatalog(force: false)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let loadError, catalog.isEmpty {
            Section {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button {
                    Task { await refreshCatalog(force: true) }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        } else if catalog.isEmpty {
            Section {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading models…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("No models returned by this runner.", systemImage: "cpu")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await refreshCatalog(force: true) }
                    } label: {
                        Label("Refresh Catalog", systemImage: "arrow.clockwise")
                    }
                }
            }
        } else {
            summarySection
            ForEach(grouped, id: \.provider) { group in
                Section(group.provider) {
                    ForEach(group.models) { model in
                        modelToggleRow(model)
                    }
                }
            }
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent("Available", value: "\(catalog.count)")
            LabeledContent(
                "Enabled for Chat",
                value: hasCuration ? "\(enabledCount)" : "All (\(catalog.count))"
            )
        } footer: {
            Text(Copy.footer)
        }
    }

    private func modelToggleRow(_ model: AgentModelOption) -> some View {
        Toggle(isOn: Binding(
            get: { enabledIDs.contains(model.id) },
            set: { on in
                if on { enabledIDs.insert(model.id) } else { enabledIDs.remove(model.id) }
                persist()
            }
        )) {
            AgentModelIdentityLabel(model: model)
        }
        .tint(Color.accentColor)
    }

    @ToolbarContentBuilder
    private var overflowMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Enable All") { setAll(enabled: true) }
                    .disabled(catalog.isEmpty)
                Button("Disable All") { setAll(enabled: false) }
                    .disabled(catalog.isEmpty)
                Button("Only Current Selection") { enableOnlyCurrent() }
                    .disabled(catalog.isEmpty || selectedModelID.isEmpty)
                Divider()
                Button("Show All in Chat (Clear Filter)", role: .destructive) {
                    clearCuration()
                }
                Button {
                    Task { await refreshCatalog(force: true) }
                } label: {
                    Label("Refresh Catalog", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Model list actions")
        }
    }

    // MARK: - Prefs

    private func loadFromPrefs() {
        if let saved = EnabledModelsPrefs.load(runnerURL: normalizedURL) {
            hasCuration = true
            enabledIDs = saved
        } else {
            hasCuration = false
            enabledIDs = Set(catalog.map(\.id))
        }
    }

    private func persist() {
        if enabledIDs.isEmpty, let first = catalog.first?.id {
            enabledIDs = [first]
        }
        hasCuration = true
        EnabledModelsPrefs.save(enabledIDs, runnerURL: normalizedURL)
    }

    private func setAll(enabled: Bool) {
        if enabled {
            enabledIDs = Set(catalog.map(\.id))
        } else if !selectedModelID.isEmpty, catalog.contains(where: { $0.id == selectedModelID }) {
            enabledIDs = [selectedModelID]
        } else if let first = catalog.first?.id {
            enabledIDs = [first]
        } else {
            enabledIDs = []
        }
        persist()
    }

    private func enableOnlyCurrent() {
        enabledIDs = selectedModelID.isEmpty
            ? Set(catalog.prefix(1).map(\.id))
            : [selectedModelID]
        persist()
    }

    private func clearCuration() {
        EnabledModelsPrefs.clear(runnerURL: normalizedURL)
        hasCuration = false
        enabledIDs = Set(catalog.map(\.id))
    }

    // MARK: - Catalog load

    private func refreshCatalog(force: Bool) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        if !force,
           agentTargetsThisRunner,
           let agent,
           agent.modelCatalogLoaded,
           !agent.modelCatalog.isEmpty {
            applyCatalog(agent.modelCatalog)
            return
        }

        if agentTargetsThisRunner, let agent {
            await agent.refreshModelCatalog(force: force || agent.needsModelCatalogRefresh)
            if !agent.modelCatalog.isEmpty {
                applyCatalog(agent.modelCatalog)
                if !force { return }
            }
        }

        do {
            let client = RunnerCoreAPIClient(baseURLString: normalizedURL, apiToken: apiToken)
            let response = try await client.sessionModels(forceRefresh: force)
            let mapped = AgentModelOption.fromResponse(response)
            applyCatalog(mapped)
            if agentTargetsThisRunner, let agent {
                agent.adoptModelCatalog(mapped, serverDefault: response.default)
            }
        } catch {
            loadError = error.localizedDescription
            if catalog.isEmpty,
               agentTargetsThisRunner,
               let agent,
               !agent.modelCatalog.isEmpty {
                applyCatalog(agent.modelCatalog)
            }
        }
    }

    private func applyCatalog(_ mapped: [AgentModelOption]) {
        catalog = mapped
        if hasCuration {
            let available = Set(mapped.map(\.id))
            let kept = enabledIDs.intersection(available)
            if kept.isEmpty, !mapped.isEmpty {
                // Stale prefs after provider switch (e.g. Zen ids vs Go catalog).
                EnabledModelsPrefs.clear(runnerURL: normalizedURL)
                hasCuration = false
                enabledIDs = available
            } else {
                enabledIDs = kept
            }
        } else {
            enabledIDs = Set(mapped.map(\.id))
        }
    }

    private enum Copy {
        static let footer =
            "Enabled models appear in the Commander picker for this runner. Disable ones you rarely use to keep the list short."
    }
}

#Preview {
    NavigationStack {
        ModelsSettingsView(
            baseURL: "http://127.0.0.1:18080",
            apiToken: "",
            agent: AgentNetworkEngine()
        )
    }
}
