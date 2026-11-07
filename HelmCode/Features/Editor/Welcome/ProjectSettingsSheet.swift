//
//  ProjectSettingsSheet.swift
//  HelmCode
//
//  Edit project display name, runner URL, optional API token, and model enablement.
//  Opened from project list long-press / context menu.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProjectSettingsSheet: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    let projectID: WorkspaceProject.ID
    @Binding var isPresented: Bool

    @State private var displayName: String = ""
    @State private var runnerURL: String = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var runnerReachable = false
    @State private var isProbingRunner = false
    @State private var modelCatalog: [AgentModelOption] = []
    /// Bumped when returning from Models so UserDefaults curation is re-read.
    @State private var modelsPrefsStamp = 0
    @State private var addDeviceTicket: SetupPairTicket?
    @State private var addDeviceBusy = false
    @State private var devices: [RunnerDeviceRecord] = []
    @State private var pendingEnrollments: [SetupPendingEnrollment] = []
    @State private var deviceBusyID: String?

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
                devicesSection
                addDeviceSection
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
            .task(id: normalizedDraftURL) {
                await pollDevices()
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    /// Re-probe when the URL draft changes.
    private var probeIdentity: String {
        normalizedDraftURL
    }

    private var credential: String {
        project?.deviceToken ?? ""
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

    private var devicesSection: some View {
        Section {
            if devices.isEmpty {
                Text(credential.isEmpty ? "Not enrolled on this iPad." : "No other devices reported.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(devices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            if device.current {
                                Text("This iPad")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !device.current {
                            Button("Revoke", role: .destructive) {
                                Task { await revoke(device) }
                            }
                            .disabled(deviceBusyID != nil)
                        }
                    }
                }
            }
            ForEach(pendingEnrollments) { enrollment in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(enrollment.deviceName) wants to join")
                    HStack {
                        Button("Allow") {
                            Task { await decide(enrollment, approve: true) }
                        }
                        Button("Deny", role: .destructive) {
                            Task { await decide(enrollment, approve: false) }
                        }
                    }
                    .disabled(deviceBusyID != nil)
                }
            }
        } header: {
            Text("Devices")
        } footer: {
            Text(Copy.devicesFooter)
        }
    }

    private var addDeviceSection: some View {
        Section {
            Button {
                Task { await issueAddDeviceQR() }
            } label: {
                if addDeviceBusy {
                    ProgressView()
                } else {
                    Label("Add device", systemImage: "qrcode")
                }
            }
            .disabled(addDeviceBusy || credential.isEmpty)
            if let ticket = addDeviceTicket {
                Text(ticket.code)
                    .font(.title2.monospaced())
                    .tracking(4)
                if let dataUrl = ticket.qrDataUrl,
                   let img = pairingQRImage(dataUrl) {
                    Image(uiImage: img)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .background(Color.white)
                }
            }
        } header: {
            Text("Pairing")
        } footer: {
            Text(Copy.addDeviceFooter)
        }
    }

    private var modelsSection: some View {
        Section {
            if runnerReachable, RunnerURL.isValid(runnerURL) {
                NavigationLink {
                    ModelsSettingsView(
                        baseURL: normalizedDraftURL,
                        apiToken: credential,
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
        let token = credential
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
                runnerId: project?.runnerId
            )

            if wasSelected {
                await WorkspaceRuntimeBridge.activateSelectedProject(
                    session: session,
                    engine: engine,
                    vfs: vfs,
                    agent: agent
                )
            } else if let saved = session.projects.first(where: { $0.id == newID }) {
                RunnerConnectionPrefs.remember(
                    url: saved.normalizedRunnerURL ?? runnerURL
                )
            }

            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func issueAddDeviceQR() async {
        addDeviceBusy = true
        defer { addDeviceBusy = false }
        errorMessage = nil
        do {
            let client = RunnerCoreAPIClient(
                baseURLString: normalizedDraftURL,
                apiToken: credential
            )
            addDeviceTicket = try await client.startDeviceInvite(url: normalizedDraftURL)
        } catch {
            errorMessage = RunnerAuthCopy.message(for: error)
        }
    }

    @MainActor
    private func pollDevices() async {
        while !Task.isCancelled {
            await refreshDevices()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    @MainActor
    private func refreshDevices() async {
        guard !credential.isEmpty, RunnerURL.isValid(runnerURL) else {
            devices = []
            pendingEnrollments = []
            return
        }
        let client = RunnerCoreAPIClient(
            baseURLString: normalizedDraftURL,
            apiToken: credential
        )
        if let listed = try? await client.listDevices() {
            devices = listed.devices
        }
        if let pending = try? await client.listPendingEnrollments() {
            pendingEnrollments = pending.enrollments
        }
    }

    @MainActor
    private func decide(_ enrollment: SetupPendingEnrollment, approve: Bool) async {
        deviceBusyID = enrollment.id
        defer { deviceBusyID = nil }
        errorMessage = nil
        let client = RunnerCoreAPIClient(
            baseURLString: normalizedDraftURL,
            apiToken: credential
        )
        do {
            if approve {
                try await client.approveEnrollment(id: enrollment.id)
            } else {
                try await client.denyEnrollment(id: enrollment.id)
            }
            await refreshDevices()
        } catch {
            errorMessage = RunnerAuthCopy.message(for: error)
        }
    }

    @MainActor
    private func revoke(_ device: RunnerDeviceRecord) async {
        deviceBusyID = device.id
        defer { deviceBusyID = nil }
        errorMessage = nil
        let client = RunnerCoreAPIClient(
            baseURLString: normalizedDraftURL,
            apiToken: credential
        )
        do {
            try await client.revokeDevice(id: device.id)
            await refreshDevices()
        } catch {
            errorMessage = RunnerAuthCopy.message(for: error)
        }
    }

#if canImport(UIKit)
    private func pairingQRImage(_ dataUrl: String) -> UIImage? {
        let prefix = "data:image/png;base64,"
        guard dataUrl.hasPrefix(prefix),
              let data = Data(base64Encoded: String(dataUrl.dropFirst(prefix.count))) else {
            return nil
        }
        return UIImage(data: data)
    }
#endif

    private enum Copy {
        static let nameFooter = "Leave empty to use the name from the runner / git remote."
        static let runnerFooter = "HTTP, VFS (/v1/vfs), Agent sessions (/v1/sessions), and Terminal share this host."
        static let devicesFooter =
            "Each device has its own token. Revoke removes that device only. If every device is gone, run setup:recover on the runner."
        static let addDeviceFooter =
            "Shows a short code for another iPad. Allow the request here before that iPad receives a token."
        static let modelsFooter =
            "Choose which models appear in the Commander picker. Does not change provider auth on the server."
        static let modelsProbingFooter = "Checking whether the Runner URL is reachable…"
        static let modelsUnavailableFooter =
            "Available when the Runner URL is reachable. Choose which models appear in the Commander picker."
    }
}
