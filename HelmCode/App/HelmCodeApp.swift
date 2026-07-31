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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkEngine)
                .environmentObject(vfsEngine)
                .onAppear {
                    // Keep VFS tunnel on the same backend host/token as the HTTP engine.
                    vfsEngine.baseURLString = networkEngine.baseURLString
                    vfsEngine.apiToken = networkEngine.apiToken
                }
        }
        #if os(iOS)
        .defaultSize(width: 1280, height: 840)
        #endif
    }
}
