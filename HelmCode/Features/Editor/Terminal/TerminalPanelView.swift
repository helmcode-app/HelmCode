//
//  TerminalPanelView.swift
//  HelmCode
//
//  Full-column WebSSH chrome for the open project with industrial multi-tab deck header,
//  integrated buffer search, on-screen tactile accessory bar, and Agent collaboration.
//

import SwiftUI
import Combine

@MainActor
final class TerminalTabItem: Identifiable, ObservableObject {
    let id: UUID
    var sessionNumber: Int
    @Published var reconnectGeneration: UInt64 = 0
    @Published var statusText: String = "disconnected"
    @Published var statusKind: TerminalLinkStatus = .info
    let controller = TerminalSessionController()
    private var cancellables = Set<AnyCancellable>()

    init(sessionNumber: Int) {
        self.id = UUID()
        self.sessionNumber = sessionNumber
        // Nested controller changes must bubble up — `@State [ObservableObject]` alone won't.
        controller.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var statusBeaconColor: Color {
        switch statusKind {
        case .ok: return .green
        case .err: return .red
        case .info:
            return statusText.contains("connect") ? .orange : .secondary
        }
    }
}

/// Owns tab objects and republishes their (and nested controller) changes to SwiftUI.
@MainActor
final class TerminalTabDeck: ObservableObject {
    @Published private(set) var tabs: [TerminalTabItem] = []
    @Published var activeTabID: UUID?
    private(set) var nextSessionNumber: Int = 1
    private var tabObservations = [UUID: AnyCancellable]()

    var activeTab: TerminalTabItem? {
        tabs.first(where: { $0.id == activeTabID }) ?? tabs.first
    }

    func ensureDefaultTab() {
        guard tabs.isEmpty else { return }
        let first = makeTab(sessionNumber: 1)
        tabs = [first]
        activeTabID = first.id
        nextSessionNumber = 2
    }

    func createTab() {
        let tab = makeTab(sessionNumber: nextSessionNumber)
        nextSessionNumber += 1
        tabs.append(tab)
        activeTabID = tab.id
    }

    /// Returns `true` when the deck is empty and the panel should hide.
    @discardableResult
    func closeTab(_ tab: TerminalTabItem) -> Bool {
        detach(tab.id)
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            tabs.remove(at: index)
            if activeTabID == tab.id {
                activeTabID = tabs.indices.contains(index)
                    ? tabs[index].id
                    : tabs.last?.id
            }
        }
        return tabs.isEmpty
    }

    func reset() {
        tabObservations.removeAll()
        tabs = []
        activeTabID = nil
        nextSessionNumber = 1
        ensureDefaultTab()
    }

    private func makeTab(sessionNumber: Int) -> TerminalTabItem {
        let tab = TerminalTabItem(sessionNumber: sessionNumber)
        attach(tab)
        return tab
    }

    private func attach(_ tab: TerminalTabItem) {
        tabObservations[tab.id] = tab.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private func detach(_ id: UUID) {
        tabObservations.removeValue(forKey: id)
    }
}

struct TerminalPanelView: View {
    @ObservedObject var engine: HelmCodeNetworkEngine
    var projectID: String
    var projectRunnerURL: String?
    /// Whether the terminal surface is visible (⌘J).
    var isVisible: Bool
    /// Workspace for `/v1/terminal?workspaceId=` (same id as VFS / sessions).
    var workspaceId: String = HelmWorkspace.defaultID
    /// Bumped when the open project changes / closes / shell exits.
    var sessionEpoch: UInt64
    /// Leave Terminal mode after remote `exit`.
    var onSessionEnded: () -> Void
    /// Return to editor without killing the session (x button).
    var onHide: () -> Void
    /// Send extracted terminal snippet/error to Commander Agent.
    var onSendToAgent: ((String) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var deck = TerminalTabDeck()
    @State private var isAskingAgent = false

    private var activeTab: TerminalTabItem? { deck.activeTab }

    private var runnerURL: String {
        TerminalEndpoint.httpBase(
            projectRunnerURL: projectRunnerURL,
            engineBaseURL: engine.baseURLString
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            deckHeader

            if let tab = activeTab, tab.controller.isSearching {
                TerminalSearchBar(controller: tab.controller)
                    .transition(.opacity)
            }

            ZStack {
                ForEach(deck.tabs) { tab in
                    let isSelected = tab.id == (deck.activeTabID ?? deck.tabs.first?.id)
                    TerminalHostView(
                        baseURLString: runnerURL,
                        apiToken: engine.apiToken,
                        workspaceId: workspaceId,
                        projectID: "\(projectID)-\(tab.id.uuidString)",
                        isDark: colorScheme == .dark,
                        reconnectGeneration: tab.reconnectGeneration,
                        sessionEpoch: sessionEpoch,
                        isVisible: isVisible && isSelected && !projectID.isEmpty,
                        controller: tab.controller,
                        onStatus: { text, kind in
                            tab.statusText = text
                            tab.statusKind = kind
                        },
                        onReadyInfo: { shell, cols, rows in
                            tab.controller.shellName = shell
                            tab.controller.gridCols = cols
                            tab.controller.gridRows = rows
                        },
                        onSessionEnded: { _ in
                            handleTabSessionEnded(tab)
                        }
                    )
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let tab = activeTab, tab.controller.showAccessoryBar {
                TerminalAccessoryBar(controller: tab.controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(.systemBackground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .onAppear {
            deck.ensureDefaultTab()
        }
        .onChange(of: projectID) { _, _ in
            deck.reset()
        }
    }

    // MARK: - Deck Header

    private var deckHeader: some View {
        HStack(spacing: 8) {
            tabsHeaderView

            Spacer(minLength: 4)

            headerTools
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
        .clipped()
    }

    // MARK: - Tabs Section

    private var tabsHeaderView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if deck.tabs.count <= 1, let tab = deck.tabs.first {
                    // Single tab: minimal badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tab.statusBeaconColor)
                            .frame(width: 6, height: 6)

                        Text("Terminal")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                } else {
                    // Multi-tab pills
                    ForEach(deck.tabs) { tab in
                        let isSelected = tab.id == (deck.activeTabID ?? deck.tabs.first?.id)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(tab.statusBeaconColor)
                                .frame(width: 6, height: 6)

                            Text("\(tab.sessionNumber): Terminal")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .lineLimit(1)

                            Button {
                                if deck.closeTab(tab) {
                                    onHide()
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (isSelected ? Color(.systemBackground) : Color(.tertiarySystemFill).opacity(0.6)),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            deck.activeTabID = tab.id
                        }
                    }
                }

                // New tab button
                Button {
                    deck.createTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            Color(.tertiarySystemFill).opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New terminal tab")
            }
        }
    }

    // MARK: - Header Tools

    /// Top bar keeps Search, accessory toggle, and Ask Agent — larger tappable chips.
    private var headerTools: some View {
        HStack(spacing: 8) {
            searchButton
            keyboardToggleButton
            if onSendToAgent != nil {
                askAgentButton
            }
        }
    }

    // MARK: - Individual Tool Items

    private var searchButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if let tab = activeTab {
                    tab.controller.isSearching.toggle()
                }
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activeTab?.controller.isSearching == true ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 28)
                .background(
                    (activeTab?.controller.isSearching == true
                        ? Color.accentColor.opacity(0.14)
                        : Color(.tertiarySystemFill)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Find in terminal")
    }

    private var keyboardToggleButton: some View {
        let isOn = activeTab?.controller.showAccessoryBar == true
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if let tab = activeTab {
                    tab.controller.showAccessoryBar.toggle()
                }
            }
        } label: {
            Image(systemName: isOn ? "keyboard.fill" : "keyboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 28)
                .background(
                    (isOn ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill)),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Toggle accessory bar")
    }

    private var askAgentButton: some View {
        Button {
            triggerSendToAgent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isAskingAgent ? "sparkles" : "sparkle")
                    .font(.system(size: 12, weight: .bold))
                Text("Ask Agent")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Color.accentColor.opacity(0.14),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Send terminal output to Agent")
    }

    // MARK: - Actions

    private func handleTabSessionEnded(_ tab: TerminalTabItem) {
        if deck.tabs.count > 1 {
            _ = deck.closeTab(tab)
        } else {
            onSessionEnded()
        }
    }

    private func triggerSendToAgent() {
        guard let tab = activeTab else { return }
        isAskingAgent = true
        tab.controller.extractSnippet { snippet in
            isAskingAgent = false
            let clean = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            let prompt = "Please help me diagnose this terminal output/error:\n\n```shell\n\(clean)\n```"
            onSendToAgent?(prompt)
        }
    }
}

// MARK: - Search Bar Component

struct TerminalSearchBar: View {
    @ObservedObject var controller: TerminalSessionController

    /// Fixed height so UITextField focus / keyboard chrome cannot resize the row.
    private let barHeight: CGFloat = 36

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            TextField("Find in terminal…", text: Binding(
                get: { controller.searchQuery },
                set: { controller.updateSearchQuery($0) }
            ))
            .font(.caption)
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit {
                controller.findNext()
            }

            Text(matchCounterLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .trailing)
                .opacity(controller.searchQuery.isEmpty ? 0 : 1)
                .accessibilityHidden(controller.searchQuery.isEmpty)

            HStack(spacing: 4) {
                Button {
                    controller.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(controller.searchQuery.isEmpty)

                Button {
                    controller.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(controller.searchQuery.isEmpty)
            }
            .foregroundStyle(.secondary)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    controller.closeSearch()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 10)
        .frame(height: barHeight)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var matchCounterLabel: String {
        if controller.searchResultCount > 0 {
            return "\(controller.searchResultIndex + 1)/\(controller.searchResultCount)"
        }
        return "0/0"
    }
}
