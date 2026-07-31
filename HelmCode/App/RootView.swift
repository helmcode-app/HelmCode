//
//  RootView.swift
//  HelmCode
//
//  App shell:
//  • NavigationSplitView — sidebar + editor detail
//  • .inspector — Commander (width on inspector content)
//  • Binds VFS/HTTP engines ↔ WorkspaceSession via WorkspaceRuntimeBridge
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RootView: View {
    @EnvironmentObject private var engine: HelmCodeNetworkEngine
    @EnvironmentObject private var vfs: VFSNetworkEngine
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
                runnerStatus: runnerStatus,
                onOpenSettings: { isSettingsPresented = true }
            )
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: commanderPresented) {
            CommanderView(engine: engine)
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
        .modifier(
            WorkspaceRuntimeModifier(
                session: session,
                engine: engine,
                vfs: vfs,
                runnerStatus: runnerStatus
            )
        )
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

// MARK: - Engine ↔ session binding

/// Keeps session projects in sync with VFS and activates the selected runner.
private struct WorkspaceRuntimeModifier: ViewModifier {
    @ObservedObject var session: WorkspaceSession
    @ObservedObject var engine: HelmCodeNetworkEngine
    @ObservedObject var vfs: VFSNetworkEngine
    @ObservedObject var runnerStatus: ProjectRunnerStatusMonitor

    func body(content: Content) -> some View {
        content
            .task {
                // Do not auto-start VFS until a project is opened.
                refreshRunnerStatus()
            }
            .onChange(of: session.selectedProjectID) { _, _ in
                Task { await activateSelectedProject() }
            }
            .onChange(of: engine.baseURLString) { _, _ in
                BackendConnectionSync.syncVFS(from: engine, to: vfs)
                refreshRunnerStatus()
            }
            .onChange(of: engine.apiToken) { _, _ in
                BackendConnectionSync.syncVFS(from: engine, to: vfs)
                refreshRunnerStatus()
            }
            .onChange(of: vfs.tree) { _, _ in
                WorkspaceRuntimeBridge.applyTree(from: vfs, engine: engine, to: session)
                refreshRunnerStatus()
            }
            .onChange(of: vfs.workspaceBranch) { _, _ in
                WorkspaceRuntimeBridge.applyMetadata(from: vfs, engine: engine, to: session)
            }
            .onChange(of: vfs.workspaceRemote) { _, _ in
                WorkspaceRuntimeBridge.applyMetadata(from: vfs, engine: engine, to: session)
            }
    }

    private func refreshRunnerStatus() {
        runnerStatus.refresh(projects: session.projects, engine: engine)
    }

    private func activateSelectedProject() async {
        await WorkspaceRuntimeBridge.activateSelectedProject(
            session: session,
            engine: engine,
            vfs: vfs
        )
        refreshRunnerStatus()
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
