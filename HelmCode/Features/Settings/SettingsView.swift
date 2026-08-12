//
//  SettingsView.swift
//  HelmCode
//
//  App settings sheet: Appearance, Layout, About.
//  Runner connection + models are project-scoped (Project Settings).
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(AppStorageKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(AppStorageKey.showCommander) private var showCommander = true

    var body: some View {
        Form {
            appearanceSection
            layoutSection
            aboutSection
        }
        .formStyle(.grouped)
        .helmInlineNavigationTitle("Settings")
        .helmSheetCloseToolbar {
            dismiss()
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section {
            Picker(selection: $appearanceRaw) {
                ForEach(AppearancePreference.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            } label: {
                EmptyView()
            }
            .helmTitlelessInlinePicker()
        } header: {
            Text("Appearance")
        } footer: {
            Text(Copy.appearanceFooter)
        }
    }

    // MARK: - Layout

    private var layoutSection: some View {
        Section {
            Toggle(isOn: $showSidebar) {
                Label("Sidebar", systemImage: "sidebar.left")
            }
            Toggle(isOn: $showCommander) {
                Label("Commander", systemImage: "sidebar.right")
            }
        } header: {
            Text("Layout")
        } footer: {
            Text(Copy.layoutFooter)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            NavigationLink {
                EditorKeyboardShortcutsView()
            } label: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }

            LabeledContent("App", value: AppBundleInfo.displayName)
            LabeledContent("Bundle", value: AppBundleInfo.bundleIdentifier)
            if let version = AppBundleInfo.shortVersion {
                LabeledContent("Version", value: version)
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Copy

    private enum Copy {
        static let appearanceFooter = "System follows the iPad light and dark mode."
        static let layoutFooter = "Drag system dividers to resize columns. Use ⌘J for Terminal when a project is open."
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
