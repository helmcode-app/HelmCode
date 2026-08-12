//
//  AgentModelPickerSheet.swift
//  HelmCode
//
//  Commander model picker sheet: curated list from Project Settings + live catalog.
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
        .presentationDetents(snapshot.count > 12 ? [.medium, .large] : [.medium])
        .presentationDragIndicator(.visible)
    }

    private func row(_ model: AgentModelOption) -> some View {
        let selected = model.id == agent.modelID
        return SelectableListRow(selected: selected) {
            agent.modelID = model.id
            isPresented = false
        } leading: {
            AgentModelIdentityLabel(
                model: model,
                titleWeight: selected ? .semibold : .regular
            )
        }
        .accessibilityLabel(model.title)
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
        if agent.needsModelCatalogRefresh {
            await agent.refreshModelCatalog(force: true)
        }
        let next = curatedModels()
        if !next.isEmpty {
            snapshot = next
        }
    }
}
