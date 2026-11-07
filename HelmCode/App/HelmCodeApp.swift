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
                    // Drop the legacy shared Bearer. Device tokens live in the Keychain.
                    UserDefaults.standard.removeObject(forKey: AppStorageKey.runnerAPIToken)
                    // VFS/Agent sockets start when a project is opened.
                    BackendConnectionSync.syncAll(from: networkEngine, vfs: vfsEngine, agent: agentEngine)
                }
                .onOpenURL { url in
                    guard RunnerPairingLink.parse(url) != nil else { return }
                    RunnerPairingInbox.pending = url
                    NotificationCenter.default.post(
                        name: .helmPairingLink,
                        object: nil,
                        userInfo: ["url": url]
                    )
                }
        }
        #if os(iOS)
        .defaultSize(width: 1280, height: 840)
        #endif
    }
}
