//
//  AgentModelPickerSheet.swift
//  HelmCode
//
//  Commander model picker sheet: catalog + think level + fast.
//

import SwiftUI

struct AgentModelPickerSheet: View {
    @ObservedObject var agent: AgentNetworkEngine
    @Binding var isPresented: Bool

    @State private var snapshot: [AgentModelOption] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !agent.availableContextLevels.isEmpty {
                    contextSection
                }
                if !agent.availableThinkingLevels.isEmpty {
                    thinkingSection
                }
                if !agent.availableThinkLevels.isEmpty {
                    thinkLevelSection
                }
                if agent.supportsFastMode {
                    fastSection
                }
                modelSection
            }
            .listStyle(.insetGrouped)
            .helmInlineNavigationTitle("Model")
            .helmSheetCloseToolbar {
                isPresented = false
            }
            .task {
                snapshot = curatedModels()
                await reload()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var modelSection: some View {
        Section {
            if isLoading, snapshot.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if snapshot.isEmpty {
                ContentUnavailableView(
                    "No Models",
                    systemImage: "cpu",
                    description: Text(
                        "Enable models in Project Settings → Models, or wait for the runner catalog to load."
                    )
                )
            } else {
                ForEach(snapshot) { model in
                    row(model)
                }
            }
        } header: {
            Text("Model")
        }
    }

    private var contextSection: some View {
        Section {
            ForEach(agent.availableContextLevels) { level in
                SelectableListRow(selected: agent.contextLevel == level) {
                    agent.contextLevel = level
                    agent.syncUsageMeterToContextLevel()
                } leading: {
                    Text(level.title)
                        .font(.body.weight(agent.contextLevel == level ? .semibold : .regular))
                }
                .accessibilityLabel(level.title)
            }
        } header: {
            Text("Context")
        }
    }

    private var thinkingSection: some View {
        Section {
            ForEach([true, false], id: \.self) { on in
                SelectableListRow(selected: agent.thinkingEnabled == on) {
                    agent.thinkingEnabled = on
                } leading: {
                    Text(on ? "On" : "Off")
                        .font(.body.weight(agent.thinkingEnabled == on ? .semibold : .regular))
                }
                .accessibilityLabel(on ? "Thinking on" : "Thinking off")
            }
        } header: {
            Text("Thinking")
        }
    }

    private var thinkLevelSection: some View {
        Section {
            ForEach(agent.availableThinkLevels) { level in
                SelectableListRow(selected: agent.thinkLevel == level) {
                    agent.thinkLevel = level
                } leading: {
                    Text(level.title)
                        .font(.body.weight(agent.thinkLevel == level ? .semibold : .regular))
                }
                .accessibilityLabel(level.title)
            }
        } header: {
            Text("Effort")
        }
    }

    private var fastSection: some View {
        Section {
            ForEach([true, false], id: \.self) { on in
                SelectableListRow(selected: agent.fastMode == on) {
                    agent.fastMode = on
                } leading: {
                    Text(on ? "On" : "Off")
                        .font(.body.weight(agent.fastMode == on ? .semibold : .regular))
                }
                .accessibilityLabel(on ? "Fast on" : "Fast off")
            }
        } header: {
            Text("Fast")
        }
    }

    private func row(_ model: AgentModelOption) -> some View {
        let selected = model.id == agent.modelID
        return SelectableListRow(selected: selected) {
            selectModel(model.id)
        } leading: {
            AgentModelIdentityLabel(
                model: model,
                titleWeight: selected ? .semibold : .regular
            )
        }
        .accessibilityLabel(model.title)
    }

    private func selectModel(_ id: String) {
        guard agent.modelID != id else { return }
        agent.modelID = id
        // Show last-known knobs for this model immediately; probe refreshes after.
        agent.applyCachedCapsForCurrentModel()
        Task {
            await agent.refreshModelCatalog(force: true, probeModel: id)
            snapshot = curatedModels()
        }
    }

    private func curatedModels() -> [AgentModelOption] {
        EnabledModelsPrefs.pickerModels(
            from: agent.modelCatalog,
            selectedID: agent.modelID,
            runnerURL: agent.baseURLString
        )
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        agent.applyCachedCapsForCurrentModel()
        let probe = agent.modelID.isEmpty ? nil : agent.modelID
        // Soft refresh when catalog already loaded — avoids racing a full
        // force discover that used to flip Effort/Fast with another model.
        await agent.refreshModelCatalog(
            force: agent.needsModelCatalogRefresh,
            probeModel: probe
        )
        let next = curatedModels()
        if !next.isEmpty {
            snapshot = next
        }
    }
}
