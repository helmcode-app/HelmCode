//
//  TerminalSessionController.swift
//  HelmCode
//
//  State and action bridge between SwiftUI terminal chrome and the xterm web view.
//

import SwiftUI
import Combine
#if canImport(UIKit)
import UIKit
#endif

enum TerminalKey: String, CaseIterable, Identifiable {
    case esc = "ESC"
    case tab = "TAB"
    case ctrlC = "^C"
    case ctrlD = "^D"
    case ctrlL = "^L"
    case up = "↑"
    case down = "↓"
    case left = "←"
    case right = "→"
    case pipe = "|"
    case tilde = "~"
    case slash = "/"
    case hyphen = "-"

    var id: String { rawValue }

    var sequence: String {
        switch self {
        case .esc: return "\u{1b}"
        case .tab: return "\t"
        case .ctrlC: return "\u{03}"
        case .ctrlD: return "\u{04}"
        case .ctrlL: return "\u{0c}"
        case .up: return "\u{1b}[A"
        case .down: return "\u{1b}[B"
        case .right: return "\u{1b}[C"
        case .left: return "\u{1b}[D"
        case .pipe: return "|"
        case .tilde: return "~"
        case .slash: return "/"
        case .hyphen: return "-"
        }
    }
}

@MainActor
final class TerminalSessionController: ObservableObject {
    weak var coordinator: TerminalHostCoordinator?

    @Published var shellName: String = "shell"
    @Published var gridCols: Int = 0
    @Published var gridRows: Int = 0
    @Published var fontSize: Int = 13
    @Published var showAccessoryBar: Bool = true
    @Published var isSearching: Bool = false
    @Published var searchQuery: String = ""
    @Published var searchResultIndex: Int = -1
    @Published var searchResultCount: Int = 0

    func bind(_ coordinator: TerminalHostCoordinator) {
        self.coordinator = coordinator
    }

    func sendInput(_ text: String) {
        coordinator?.sendInput(text)
    }

    func sendKey(_ key: TerminalKey) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        sendInput(key.sequence)
    }

    func clear() {
        coordinator?.clear()
    }

    func setFontSize(_ size: Int) {
        fontSize = max(10, min(22, size))
        coordinator?.setFontSize(fontSize)
    }

    func increaseFontSize() {
        setFontSize(fontSize + 1)
    }

    func decreaseFontSize() {
        setFontSize(fontSize - 1)
    }

    func extractSnippet(completion: @escaping (String) -> Void) {
        guard let coordinator else {
            completion("")
            return
        }
        coordinator.extractSnippet(completion: completion)
    }

    // MARK: - Search

    func findNext() {
        guard !searchQuery.isEmpty else { return }
        coordinator?.findNext(query: searchQuery)
    }

    func findPrevious() {
        guard !searchQuery.isEmpty else { return }
        coordinator?.findPrevious(query: searchQuery)
    }

    func updateSearchQuery(_ query: String) {
        searchQuery = query
        if query.isEmpty {
            searchResultIndex = -1
            searchResultCount = 0
            coordinator?.clearSearch()
        } else {
            coordinator?.findNext(query: query, incremental: true)
        }
    }

    func closeSearch() {
        isSearching = false
        searchQuery = ""
        searchResultIndex = -1
        searchResultCount = 0
        coordinator?.clearSearch()
    }
}
