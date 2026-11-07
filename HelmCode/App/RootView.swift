//
//  RootView.swift
//  HelmCode
//
//  App shell:
//  • NavigationSplitView — sidebar + editor detail
//  • .inspector — Commander (Agent command panel + streaming timeline)
//  • Engine ↔ session binding: WorkspaceRuntimeModifier
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var engine: HelmCodeNetworkEngine
    @EnvironmentObject private var vfs: VFSNetworkEngine
    @EnvironmentObject private var agent: AgentNetworkEngine
    @StateObject private var session = WorkspaceSession()
    @StateObject private var runnerStatus = ProjectRunnerStatusMonitor()

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

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                runnerStatus: runnerStatus,
                onOpenSettings: { isSettingsPresented = true }
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
                agent: agent,
                runnerStatus: runnerStatus,
                columnVisibility: $columnVisibility,
                onOpenSettings: { isSettingsPresented = true }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: commanderPresented) {
            CommanderView(engine: engine, agent: agent, session: session)
                // Let Liquid Glass sample the column content (do not force opaque fill).
                .inspectorColumnWidth(
                    min: CGFloat(LayoutMetrics.commanderWidthRange.lowerBound),
                    ideal: CGFloat(commanderWidth),
                    max: CGFloat(LayoutMetrics.commanderWidthRange.upperBound)
                )
        }
        .preferredColorScheme(appearance.preferredColorScheme)
        .sheet(isPresented: $isSettingsPresented) {
            NavigationStack {
                SettingsView()
            }
        }
        .modifier(
            WorkspaceRuntimeModifier(
                session: session,
                engine: engine,
                vfs: vfs,
                agent: agent,
                runnerStatus: runnerStatus
            )
        )
        .onAppear {
            applySidebarVisibility(showSidebar)
        }
        .onChange(of: showSidebar) { _, show in
            applySidebarVisibility(show, animated: !isSettingsPresented)
        }
        .onChange(of: columnVisibility) { _, visibility in
            // Sheet presentation can flicker column visibility. Don't write that
            // back into AppStorage or the sidebar (and its tabs) animate.
            guard !isSettingsPresented else { return }
            let visible = visibility != .detailOnly
            if showSidebar != visible {
                showSidebar = visible
            }
        }
    }

    private func applySidebarVisibility(_ show: Bool, animated: Bool = true) {
        let target: NavigationSplitViewVisibility = show ? .all : .detailOnly
        guard columnVisibility != target else { return }
        if animated {
            withAnimation(LayoutMetrics.panelSlideAnimation) {
                columnVisibility = target
            }
        } else {
            columnVisibility = target
        }
    }
}

#Preview("System") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .environmentObject(VFSNetworkEngine())
        .environmentObject(AgentNetworkEngine())
}

#Preview("Light") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .environmentObject(VFSNetworkEngine())
        .environmentObject(AgentNetworkEngine())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    RootView()
        .environmentObject(HelmCodeNetworkEngine())
        .environmentObject(VFSNetworkEngine())
        .environmentObject(AgentNetworkEngine())
        .preferredColorScheme(.dark)
}
