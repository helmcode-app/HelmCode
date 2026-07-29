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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(networkEngine)
        }
        #if os(iOS)
        .defaultSize(width: 1280, height: 840)
        #endif
    }
}
