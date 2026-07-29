//
//  SettingsView.swift
//  HelmCode
//
//  Sheet: appearance, layout, backend, about (+ keyboard shortcuts).
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(AppStorageKey.showCommander) private var showCommander = true
    @AppStorage(AppStorageKey.sidebarWidth) private var sidebarWidth = LayoutMetrics.defaultSidebarWidth
    @AppStorage(AppStorageKey.commanderWidth) private var commanderWidth = LayoutMetrics.defaultCommanderWidth

    @State private var draftBaseURL: String = ""
    @State private var draftToken: String = ""
    @State private var isRefreshing = false

    var body: some View {
        Form {
            appearanceSection
            layoutSection
            backendSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
        .onAppear {
            draftBaseURL = engine.baseURLString
            draftToken = engine.apiToken
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $appearanceRaw) {
                ForEach(AppearancePreference.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows the iPad light/dark setting.")
        }
    }

    private var layoutSection: some View {
        Section {
            Toggle(isOn: $showSidebar) {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            Toggle(isOn: $showCommander) {
                Label("Commander", systemImage: "sidebar.right")
            }
            Button("Reset Column Widths") {
                sidebarWidth = LayoutMetrics.defaultSidebarWidth
                commanderWidth = LayoutMetrics.defaultCommanderWidth
            }
        } header: {
            Text("Workspace Layout")
        } footer: {
            Text("Sidebar and Commander use system NavigationSplitView / inspector chrome. Drag system dividers to resize.")
        }
    }

    private var backendSection: some View {
        Section {
            TextField("Base URL", text: $draftBaseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .onSubmit { applyBackendDraft() }

            SecureField("API Token (optional)", text: $draftToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .onSubmit { applyBackendDraft() }

            Button {
                applyBackendDraft()
            } label: {
                Label("Apply Connection", systemImage: "link")
            }

            HStack {
                ConnectionStatusDot(state: engine.connectionState)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.connectionState.shortTitle)
                    if let health = engine.health {
                        Text("\(health.mode.rawValue) · v\(health.version)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await refreshHealth() }
                } label: {
                    if isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .accessibilityLabel("Refresh health")
            }
        } header: {
            Text("Backend")
        } footer: {
            Text("Connects to runner-core open-core HTTP (default http://127.0.0.1:8080). Bearer token is required when OPENCORE_API_TOKEN is set.")
        }
    }

    private var aboutSection: some View {
        Section {
            NavigationLink {
                EditorKeyboardShortcutsView()
            } label: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }
            LabeledContent("App", value: "HelmCode")
            LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                LabeledContent("Version", value: version)
            }
        } header: {
            Text("About")
        } footer: {
            Text("Editor shortcuts need focus in the code pane and a hardware keyboard.")
        }
    }

    // MARK: - Backend

    private func applyBackendDraft() {
        let url = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty {
            engine.baseURLString = url
        }
        engine.apiToken = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await refreshHealth() }
    }

    private func refreshHealth() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await engine.checkBackendHealth()
    }
}

#Preview {
    NavigationStack {
        SettingsView(engine: HelmCodeNetworkEngine())
    }
}
