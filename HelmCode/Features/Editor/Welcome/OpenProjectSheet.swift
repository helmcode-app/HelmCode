//
//  OpenProjectSheet.swift
//  HelmCode
//
//  Open Project: Hosted (reserved) | Self-hosted (runner URL + optional token).
//  This is the only place to bind a workspace to a runner-core instance.
//  Form pieces: OpenProjectSelfHostedForm, OpenProjectHostedPlaceholder.
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
            OpenProjectHostedPlaceholder()
        case .selfHosted:
            OpenProjectSelfHostedForm(
                runnerURL: $runnerURL,
                apiToken: $apiToken,
                isConnecting: isConnecting,
                onConfirm: { Task { await connectSelfHosted() } }
            )
        }
    }

    // MARK: - Connect

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
