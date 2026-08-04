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
    /// Comma-separated project ids, most-recent first.
    static let recentProjectIDs = "helm.workspace.recentProjectIDs"
    /// JSON-encoded `[SavedProjectRecord]` (Open Project list; trees reloaded from VFS).
    static let savedProjects = "helm.workspace.savedProjects"
    /// Last open project id (restored on launch when still in the saved list).
    static let lastSelectedProjectID = "helm.workspace.lastSelectedProjectID"
    /// JSON-encoded `[WorkspaceBookmark]`.
    static let workspaceBookmarks = "helm.workspace.bookmarks"
    /// Selected sidebar navigator tab (`SidebarNavigator.rawValue`).
    static let sidebarNavigator = "helm.sidebar.navigator"
    /// Last successful Open Project runner URL (prefill only).
    static let lastRunnerURL = "helm.runner.lastURL"
    /// Optional Bearer for open-core (`OPENCORE_API_TOKEN`); applied when opening / reactivating projects.
    static let runnerAPIToken = "helm.runner.apiToken"
    /// Center column shows Terminal instead of the code editor when true.
    static let showTerminal = "helm.column.showTerminal"
}

// MARK: - Last self-hosted runner (Open Project)

enum RunnerConnectionPrefs {
    static let defaultURL = "http://127.0.0.1:18080"

    static func lastURL(defaults: UserDefaults = .standard) -> String {
        let raw = defaults.string(forKey: AppStorageKey.lastRunnerURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if RunnerURL.isValid(raw) {
            return RunnerURL.normalizeHTTP(raw)
        }
        return defaultURL
    }

    static func apiToken(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AppStorageKey.runnerAPIToken)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func remember(url: String, token: String, defaults: UserDefaults = .standard) {
        let normalized = RunnerURL.normalizeHTTP(url)
        if RunnerURL.isValid(normalized) {
            defaults.set(normalized, forKey: AppStorageKey.lastRunnerURL)
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: AppStorageKey.runnerAPIToken)
        } else {
            defaults.set(trimmed, forKey: AppStorageKey.runnerAPIToken)
        }
    }
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
