//
//  OpenProjectSheet.swift
//  HelmCode
//
//  Open Project: Hosted (reserved) | Self-hosted (runner-core URL).
//  Tabs use the same large iOS segmented control as the sidebar navigator.
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
    @Binding var isPresented: Bool

    @State private var tab: OpenProjectDeploymentTab = .selfHosted
    @State private var runnerURL: String = ""
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
            .navigationTitle("Open Project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .helmSheetCloseToolbar(disabled: isConnecting) {
                isPresented = false
            }
            .onAppear {
                if runnerURL.isEmpty {
                    runnerURL = engine.baseURLString
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
                TextField("https://runner.example.com:8080", text: $runnerURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .disabled(isConnecting)
            } header: {
                Text("Runner URL")
            } footer: {
                Text("Point at your open-core runner-core instance. VFS uses the same host at /v1/vfs.")
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

        do {
            _ = try await VFSConnect.openSelfHosted(
                urlString: runnerURL,
                engine: engine,
                vfs: vfs,
                session: session
            )
            isPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
