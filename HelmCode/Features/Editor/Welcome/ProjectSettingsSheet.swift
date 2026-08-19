//
//  ProjectSettingsSheet.swift
//  HelmCode
//
//  Edit project display name, runner URL, optional API token, and model enablement.
//  Opened from project list long-press / context menu.
//

import SwiftUI

struct ProjectSettingsSheet: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    let projectID: WorkspaceProject.ID
    @Binding var isPresented: Bool

    @State private var displayName: String = ""
    @State private var runnerURL: String = ""
    @State private var apiToken: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var runnerReachable = false
    @State private var isProbingRunner = false
    @State private var modelCatalog: [AgentModelOption] = []
    /// Bumped when returning from Models so UserDefaults curation is re-read.
    @State private var modelsPrefsStamp = 0

    private var project: WorkspaceProject? {
        session.projects.first { $0.id == projectID }
    }

    private var normalizedDraftURL: String {
        RunnerURL.normalizeHTTP(runnerURL)
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                runnerURLSection
                tokenSection
                modelsSection
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .helmInlineNavigationTitle("Project Settings")
            .helmSheetCloseToolbar(disabled: isSaving) {
                isPresented = false
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        Group {
                            if isSaving {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                            }
                        }
                    }
                    .accessibilityLabel("Save")
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear(perform: loadFields)
            .task(id: probeIdentity) {
                await probeRunner()
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// Re-probe when URL or token draft changes.
    private var probeIdentity: String {
        "\(normalizedDraftURL)|\(apiToken)"
    }

    private var nameSection: some View {
        Section {
            TextField("Display name", text: $displayName)
                .disabled(isSaving)
        } header: {
            Text("Name")
        } footer: {
            Text(Copy.nameFooter)
        }
    }

    private var runnerURLSection: some View {
        Section {
            TextField("http://127.0.0.1:18080", text: $runnerURL)
                .helmURLFieldStyle()
                .disabled(isSaving)
        } header: {
            Text("Runner URL")
        } footer: {
            Text(Copy.runnerFooter)
        }
    }

    private var tokenSection: some View {
        Section {
            SecureField("Bearer token (optional)", text: $apiToken)
                .helmMonospacedFieldStyle()
                .disabled(isSaving)
                .textContentType(.password)
        } header: {
            Text("API Token")
        } footer: {
            Text(Copy.tokenFooter)
        }
    }

    private var modelsSection: some View {
        Section {
            if runnerReachable, RunnerURL.isValid(runnerURL) {
                NavigationLink {
                    ModelsSettingsView(
                        baseURL: normalizedDraftURL,
                        apiToken: apiToken,
                        agent: agent
                    )
                    .onDisappear {
                        syncModelsCatalogFromAgent()
                        modelsPrefsStamp += 1
                    }
                } label: {
                    HStack {
                        Label("Models", systemImage: "cpu")
                        Spacer()
                        if let label = modelsCountLabel {
                            Text(label)
                                .foregroundStyle(.secondary)
                                .font(.body.monospacedDigit())
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                Label {
                    HStack {
                        Text("Models")
                        if isProbingRunner {
                            Spacer(minLength: 8)
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                } icon: {
                    Image(systemName: "cpu")
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Agent")
        } footer: {
            Text(modelsFooterText)
        }
    }

    private var modelsCountLabel: String? {
        _ = modelsPrefsStamp
        return EnabledModelsPrefs.enabledOverAvailableLabel(
            catalog: modelCatalog,
            runnerURL: normalizedDraftURL
        )
    }

    private var modelsFooterText: String {
        if runnerReachable, RunnerURL.isValid(runnerURL) {
            return Copy.modelsFooter
        }
        if isProbingRunner {
            return Copy.modelsProbingFooter
        }
        return Copy.modelsUnavailableFooter
    }

    private func loadFields() {
        guard let project else {
            isPresented = false
            return
        }
        displayName = project.customName ?? ""
        runnerURL = project.normalizedRunnerURL ?? project.runnerBaseURL ?? ""
        apiToken = project.apiToken ?? ""
    }

    private var canSave: Bool {
        RunnerURL.isValid(runnerURL)
    }

    @MainActor
    private func probeRunner() async {
        guard RunnerURL.isValid(runnerURL) else {
            runnerReachable = false
            isProbingRunner = false
            return
        }
        isProbingRunner = true
        defer { isProbingRunner = false }
        let url = normalizedDraftURL
        let token = apiToken
        let online = await RunnerHealthProbe.isReachable(baseURL: url, apiToken: token)
        // Ignore stale results if the user edited the URL mid-probe.
        guard RunnerURL.normalizeHTTP(runnerURL) == url else { return }
        runnerReachable = online
        if online {
            await refreshModelsCatalog(url: url, token: token)
        } else {
            modelCatalog = []
        }
    }

    private var agentTargetsDraftRunner: Bool {
        let active = RunnerURL.normalizeHTTP(agent.baseURLString)
        return !active.isEmpty && active == normalizedDraftURL
    }

    private func syncModelsCatalogFromAgent() {
        guard agentTargetsDraftRunner, !agent.modelCatalog.isEmpty else { return }
        modelCatalog = agent.modelCatalog
    }

    @MainActor
    private func refreshModelsCatalog(url: String, token: String) async {
        if agentTargetsDraftRunner,
           agent.modelCatalogLoaded,
           !agent.modelCatalog.isEmpty {
            modelCatalog = agent.modelCatalog
        }
        do {
            let client = RunnerCoreAPIClient(baseURLString: url, apiToken: token)
            let response = try await client.sessionModels()
            let mapped = AgentModelOption.fromResponse(response)
            guard RunnerURL.normalizeHTTP(runnerURL) == url else { return }
            if !mapped.isEmpty {
                modelCatalog = mapped
            }
        } catch {
            // Keep whatever we already have (agent catalog or empty).
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let wasSelected = session.selectedProjectID == projectID

        do {
            let newID = try session.updateProjectSettings(
                id: projectID,
                customName: displayName,
                runnerURL: runnerURL,
                apiToken: apiToken
            )

            if wasSelected {
                await WorkspaceRuntimeBridge.activateSelectedProject(
                    session: session,
                    engine: engine,
                    vfs: vfs,
                    agent: agent
                )
            } else if let project = session.projects.first(where: { $0.id == newID }),
                      let token = project.apiToken,
                      !token.isEmpty {
                // Keep global remembered token in sync for other open flows.
                RunnerConnectionPrefs.remember(
                    url: project.normalizedRunnerURL ?? runnerURL,
                    token: token
                )
            }

            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private enum Copy {
        static let nameFooter = "Leave empty to use the name from the runner / git remote."
        static let runnerFooter = "HTTP, VFS (/v1/vfs), Agent sessions (/v1/sessions), and Terminal share this host."
        static let tokenFooter = "Required only when the runner sets OPENCORE_API_TOKEN."
        static let modelsFooter =
            "Choose which models appear in the Commander picker. Does not change provider auth on the server."
        static let modelsProbingFooter = "Checking whether the Runner URL is reachable…"
        static let modelsUnavailableFooter =
            "Available when the Runner URL is reachable. Choose which models appear in the Commander picker."
    }
}
