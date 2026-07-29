//
//  RootView.swift
//  HelmCode
//
//  App shell — system NavigationSplitView sidebar + feature detail canvas.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var engine: HelmCodeNetworkEngine
    @StateObject private var session = WorkspaceSession()

    @State private var isSettingsPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @AppStorage(AppStorageKey.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppStorageKey.showSidebar) private var showSidebar = true
    @AppStorage(AppStorageKey.sidebarWidth) private var sidebarWidth = LayoutMetrics.defaultSidebarWidth

    private var appearance: AppearancePreference {
        AppearancePreference.resolve(appearanceRaw)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                session: session,
                engine: engine,
                onOpenSettings: { isSettingsPresented = true }
            )
            .navigationSplitViewColumnWidth(
                min: LayoutMetrics.sidebarWidthRange.lowerBound,
                ideal: sidebarWidth,
                max: LayoutMetrics.sidebarWidthRange.upperBound
            )
        } detail: {
            DetailCanvasView(
                session: session,
                engine: engine,
                onOpenSettings: { isSettingsPresented = true }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(appearance.preferredColorScheme)
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView(engine: engine)
            }
            .preferredColorScheme(appearance.preferredColorScheme)
        }
        .task {
            await engine.checkBackendHealth()
        }
        .onAppear {
            applySidebarVisibility(showSidebar)
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
}

#Preview("Light") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .preferredColorScheme(.dark)
}
