//
//  RootView.swift
//  HelmCode
//
//  App shell:
//  • NavigationSplitView — sidebar + editor detail
//  • .inspector — Commander (width on inspector content)
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {
    @EnvironmentObject private var engine: HelmCodeNetworkEngine
    @EnvironmentObject private var vfs: VFSNetworkEngine
    @StateObject private var session = WorkspaceSession()

    @State private var isSettingsPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @AppStorage(AppStorageKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(AppStorageKey.showCommander) private var showCommander = true
    @AppStorage(AppStorageKey.sidebarWidth) private var sidebarWidth = LayoutMetrics.defaultSidebarWidth
    @AppStorage(AppStorageKey.commanderWidth) private var commanderWidth = LayoutMetrics.defaultCommanderWidth

    private var appearance: AppearancePreference {
        AppearancePreference.resolve(appearanceRaw)
    }

    private var commanderPresented: Binding<Bool> {
        Binding(
            get: { showCommander },
            set: { newValue in
                withAnimation(LayoutMetrics.panelSlideAnimation) {
                    showCommander = newValue
                }
            }
        )
    }

    private func openSettings() {
        isSettingsPresented = true
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                session: session,
                vfs: vfs,
                onOpenSettings: openSettings
            )
            .navigationSplitViewColumnWidth(
                min: LayoutMetrics.sidebarWidthRange.lowerBound,
                ideal: sidebarWidth,
                max: LayoutMetrics.sidebarWidthRange.upperBound
            )
        } detail: {
            EditorDetailView(
                session: session,
                engine: engine,
                vfs: vfs,
                onOpenSettings: openSettings
            )
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: commanderPresented) {
            CommanderView(engine: engine)
                // Keep inspector chrome the same fill when keyboard shifts content.
                .containerBackground(Color(.systemBackground), for: .navigation)
                .inspectorColumnWidth(
                    min: CGFloat(LayoutMetrics.commanderWidthRange.lowerBound),
                    ideal: CGFloat(commanderWidth),
                    max: CGFloat(LayoutMetrics.commanderWidthRange.upperBound)
                )
        }
        .preferredColorScheme(appearance.preferredColorScheme)
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(engine: engine, vfs: vfs)
            }
            .preferredColorScheme(appearance.preferredColorScheme)
        }
        .task {
            await engine.checkBackendHealth()
            syncVFSConfig()
            vfs.start()
        }
        .onChange(of: engine.baseURLString) { _, _ in
            syncVFSConfig()
        }
        .onChange(of: engine.apiToken) { _, _ in
            syncVFSConfig()
        }
        .onChange(of: vfs.tree) { _, tree in
            guard let tree, let root = vfs.workspaceRoot else { return }
            session.applyVFSTree(tree, remoteRoot: root)
        }
        .onAppear {
            applySidebarVisibility(showSidebar)
            syncVFSConfig()
        }
        .onChange(of: showSidebar) { _, show in
            applySidebarVisibility(show)
        }
        .onChange(of: columnVisibility) { _, visibility in
            let visible = visibility != .detailOnly
            if showSidebar != visible {
                showSidebar = visible
            }
        }
    }

    private func syncVFSConfig() {
        vfs.baseURLString = engine.baseURLString
        vfs.apiToken = engine.apiToken
    }

    private func applySidebarVisibility(_ show: Bool) {
        let target: NavigationSplitViewVisibility = show ? .all : .detailOnly
        if columnVisibility != target {
            withAnimation(LayoutMetrics.panelSlideAnimation) {
                columnVisibility = target
            }
        }
    }
}

#Preview("System") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .environmentObject(VFSNetworkEngine())
}

#Preview("Light") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .environmentObject(VFSNetworkEngine())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .environmentObject(VFSNetworkEngine())
        .preferredColorScheme(.dark)
}
