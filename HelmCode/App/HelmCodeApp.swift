//
//  HelmCodeApp.swift
//  HelmCode
//
//  Application entry point.
//

import SwiftUI

@main
struct HelmCodeApp: App {
    @StateObject private var networkEngine = HelmCodeNetworkEngine()
    @StateObject private var vfsEngine = VFSNetworkEngine()
    @StateObject private var agentEngine = AgentNetworkEngine()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkEngine)
                .environmentObject(vfsEngine)
                .environmentObject(agentEngine)
                .onAppear {
                    // Restore last Open Project token (URL lives on each saved project).
                    let token = RunnerConnectionPrefs.apiToken()
                    if !token.isEmpty {
                        networkEngine.apiToken = token
                    }
                    // Credentials only — VFS/Agent sockets start when a project is opened.
                    BackendConnectionSync.syncAll(from: networkEngine, vfs: vfsEngine, agent: agentEngine)
                }
        }
        #if os(iOS)
        .defaultSize(width: 1280, height: 840)
        #endif
    }
}
