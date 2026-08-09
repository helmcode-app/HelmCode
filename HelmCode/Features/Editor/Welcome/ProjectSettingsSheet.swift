//
//  ProjectSettingsSheet.swift
//  HelmCode
//
//  Edit project display name, runner URL, and optional API token.
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

    private var project: WorkspaceProject? {
        session.projects.first { $0.id == projectID }
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                runnerURLSection
                tokenSection
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
                    Button("Save") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave || isSaving)
                }
            }
            .onAppear(perform: loadFields)
            .interactiveDismissDisabled(isSaving)
        }
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
    }
}
