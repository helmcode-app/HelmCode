//
//  SidebarSearchView.swift
//  HelmCode
//
//  Project-wide search navigator (Xcode / VS Code Find in Workspace).
//  Match Case / Whole Word are clickable labels inside the search field.
//

import SwiftUI

struct SidebarSearchView: View {
    @ObservedObject var session: WorkspaceSession
    let project: WorkspaceProject

    @State private var query = ""
    @State private var caseSensitive = false
    @State private var matchWholeWord = false
    @State private var groups: [ProjectSearchFileGroup] = []
    @State private var hasSearched = false

    private enum Metrics {
        /// Magnifying glass ↔ field ↔ option cluster.
        static let fieldClusterSpacing: CGFloat = 4
        /// Aa ↔ W ↔ clear (and W → trailing edge via padding).
        static let optionSpacing: CGFloat = 6
        static let fieldHorizontalPadding: CGFloat = 8
        static let fieldVerticalPadding: CGFloat = 6
        static let headerHorizontalPadding: CGFloat = 10
        static let searchDebounceNanoseconds: UInt64 = 180_000_000
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchCount: Int {
        groups.reduce(0) { $0 + $1.matches.count }
    }

    private var resultSummary: String {
        if matchCount == 0 { return "No results" }
        let fileWord = groups.count == 1 ? "file" : "files"
        let matchWord = matchCount == 1 ? "result" : "results"
        return "\(matchCount) \(matchWord) in \(groups.count) \(fileWord)"
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            resultsList
        }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: caseSensitive) { _, _ in runSearch() }
        .onChange(of: matchWholeWord) { _, _ in runSearch() }
        .onChange(of: project.id) { _, _ in runSearch() }
    }

    // MARK: - Header

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            searchField
            if hasSearched, !trimmedQuery.isEmpty {
                Text(resultSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, Metrics.headerHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        HStack(spacing: Metrics.fieldClusterSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { runSearch() }

            HStack(spacing: Metrics.optionSpacing) {
                SearchMatchOptionLabel(title: "Aa", help: "Match Case", isOn: $caseSensitive)
                SearchMatchOptionLabel(title: "W", help: "Match Whole Word", isOn: $matchWholeWord)
                if !query.isEmpty {
                    clearButton
                }
            }
        }
        .padding(.horizontal, Metrics.fieldHorizontalPadding)
        .padding(.vertical, Metrics.fieldVerticalPadding)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }

    private var clearButton: some View {
        Button {
            query = ""
            groups = []
            hasSearched = false
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Search")
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        if trimmedQuery.isEmpty {
            emptyState(
                title: "Search in Project",
                subtitle: "Find text across files in \(project.name)."
            )
        } else if hasSearched, groups.isEmpty {
            emptyState(
                title: "No Results",
                subtitle: "No matches for “\(trimmedQuery)”."
            )
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.matches) { match in
                            Button {
                                session.openFile(match.nodeID, revealLine: match.line)
                            } label: {
                                matchRow(match)
                            }
                        }
                    } header: {
                        fileHeader(group)
                    }
                }
            }
            .helmSidebarListStyle()
        }
    }

    private func fileHeader(_ group: ProjectSearchFileGroup) -> some View {
        HStack(spacing: 6) {
            Image(systemName: WorkspaceNodeIconStyle.systemImage(forLanguageHint: group.languageHint))
                .foregroundStyle(WorkspaceNodeIconStyle.color(forLanguageHint: group.languageHint))
            Text(group.fileName)
                .font(.subheadline.weight(.semibold))
            Text("\(group.matches.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .textCase(nil)
    }

    private func matchRow(_ match: ProjectSearchMatch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(match.line)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, alignment: .trailing)
            Text(match.lineText.isEmpty ? " " : match.lineText)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search

    private func scheduleSearch() {
        let snapshot = query
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Metrics.searchDebounceNanoseconds)
            guard snapshot == query else { return }
            runSearch()
        }
    }

    private func runSearch() {
        guard !trimmedQuery.isEmpty else {
            groups = []
            hasSearched = false
            return
        }
        groups = ProjectSearch.search(
            project: project,
            query: trimmedQuery,
            caseSensitive: caseSensitive,
            matchWholeWord: matchWholeWord
        )
        hasSearched = true
    }
}

// MARK: - Match option label

/// Clickable text (not a bordered button): accent when on, secondary when off.
private struct SearchMatchOptionLabel: View {
    let title: String
    let help: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
