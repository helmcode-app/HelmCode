//
//  SettingsView.swift
//  HelmCode
//
//  Sheet: appearance, layout, about (+ keyboard shortcuts).
//  Runner URL / token live on Open Project (project-scoped), not here.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(AppStorageKey.showCommander) private var showCommander = true
    @AppStorage(AppStorageKey.sidebarWidth) private var sidebarWidth = LayoutMetrics.defaultSidebarWidth
    @AppStorage(AppStorageKey.commanderWidth) private var commanderWidth = LayoutMetrics.defaultCommanderWidth

    var body: some View {
        Form {
            appearanceSection
            layoutSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .helmSheetCloseToolbar {
            dismiss()
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
            Text("Self-hosted runner URL and optional API token are set when you Open Project. Editor shortcuts need focus in the code pane and a hardware keyboard.")
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
