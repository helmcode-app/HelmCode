//
//  AppPreferences.swift
//  HelmCode
//
//  Centralized UserDefaults keys + layout metrics for Settings / shell.
//

import Foundation
import SwiftUI

// MARK: - Storage keys

enum AppStorageKey {
    static let appearance = "helm.appearance"
    static let showSidebar = "helm.column.showSidebar"
    static let showCommander = "helm.column.showCommander"
    static let sidebarWidth = "helm.column.sidebarWidth"
    static let commanderWidth = "helm.column.commanderWidth"
}

// MARK: - Layout metrics

enum LayoutMetrics {
    static let sidebarWidthRange: ClosedRange<Double> = 220...420
    /// System `.inspector` column width bounds (applied on inspector content).
    static let commanderWidthRange: ClosedRange<Double> = 280...1100
    static let defaultSidebarWidth: Double = 280
    static let defaultCommanderWidth: Double = 400
    /// Horizontal inset around the CodeMirror host in the editor column.
    static let editorHorizontalInset: CGFloat = 4

    /// Matches NavigationSplitView sidebar show/hide feel (commander inspector slide).
    static var panelSlideAnimation: Animation {
        .smooth(duration: 0.32, extraBounce: 0)
    }
}

// MARK: - Appearance

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// `nil` lets the app track the system appearance.
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static func resolve(_ raw: String) -> AppearancePreference {
        AppearancePreference(rawValue: raw) ?? .system
    }
}
