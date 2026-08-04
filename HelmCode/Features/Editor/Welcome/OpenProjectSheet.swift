//
//  OpenProjectSheet.swift
//  HelmCode
//
//  Open Project: Hosted (reserved) | Self-hosted (runner URL + optional token).
//  This is the only place to bind a workspace to a runner-core instance.
//

import SwiftUI

private enum OpenProjectDeploymentTab: String, CaseIterable, Identifiable {
    case hosted
    case selfHosted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hosted: return "Hosted"
        case .selfHosted: return "Self-hosted"
        }
    }
}

struct OpenProjectSheet: View {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var agent: AgentNetworkEngine
    @Binding var isPresented: Bool

    @State private var tab: OpenProjectDeploymentTab = .selfHosted
    @State private var runnerURL: String = ""
    @State private var apiToken: String = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                deploymentPicker
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))
            .helmInlineNavigationTitle("Open Project")
            .helmSheetCloseToolbar(disabled: isConnecting) {
                isPresented = false
            }
            .onAppear {
                if runnerURL.isEmpty {
                    runnerURL = RunnerConnectionPrefs.lastURL()
                }
                if apiToken.isEmpty {
                    apiToken = RunnerConnectionPrefs.apiToken()
                }
            }
            .alert(
                "Couldn’t connect",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Chrome

    private var deploymentPicker: some View {
        Picker("Deployment", selection: $tab) {
            ForEach(OpenProjectDeploymentTab.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .helmLargeSegmentedStyle()
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .hosted:
            hostedPlaceholder
        case .selfHosted:
            selfHostedForm
        }
    }

    // MARK: - Hosted (reserved)

    private var hostedPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "cloud")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("HelmCode Hosted")
                .font(.title3.weight(.semibold))
            Text("Connect to managed runners in the cloud. This option will be available in a future release.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Coming soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .padding(.horizontal, 20)
    }

    // MARK: - Self-hosted

    private var selfHostedForm: some View {
        Form {
            Section {
                TextField("http://127.0.0.1:18080", text: $runnerURL)
                    .helmURLFieldStyle()
                    .disabled(isConnecting)
            } header: {
                Text("Runner URL")
            } footer: {
                Text("Docker compose publishes host port 18080 → container 8080. Same host serves HTTP, VFS (/v1/vfs), and Agent (/v1/agent).")
            }

            Section {
                SecureField("Bearer token (optional)", text: $apiToken)
                    .helmMonospacedFieldStyle()
                    .disabled(isConnecting)
                    .textContentType(.password)
            } header: {
                Text("API Token")
            } footer: {
                Text("Required only when the runner sets OPENCORE_API_TOKEN. Leave empty for unauthenticated local dev.")
            }

            Section {
                Button {
                    Task { await connectSelfHosted() }
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.trailing, 8)
                            Text("Connecting…")
                        } else {
                            Text("Confirm")
                                .fontWeight(.semibold)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .disabled(!canConfirm || isConnecting)
            }
        }
        .formStyle(.grouped)
    }

    private var canConfirm: Bool {
        RunnerURL.isValid(runnerURL)
    }

    @MainActor
    private func connectSelfHosted() async {
        isConnecting = true
        defer { isConnecting = false }

        let url = RunnerURL.normalizeHTTP(runnerURL)
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            _ = try await VFSConnect.openSelfHosted(
                urlString: url,
                token: token.isEmpty ? nil : token,
                engine: engine,
                vfs: vfs,
                session: session,
                agent: agent
            )
            RunnerConnectionPrefs.remember(url: url, token: token)
            // Stamp token onto the opened project so Project Settings / reopen use it.
            if let id = session.selectedProjectID,
               let project = session.projects.first(where: { $0.id == id }) {
                _ = try? session.updateProjectSettings(
                    id: id,
                    customName: project.customName ?? "",
                    runnerURL: url,
                    apiToken: token
                )
            }
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
