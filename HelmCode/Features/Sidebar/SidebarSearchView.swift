//
//  SidebarSearchView.swift
//  HelmCode
//
//  Project-wide search navigator (Xcode / VS Code Find in Workspace).
//  Field chrome: Shared/UI/HelmSearchFieldChrome.swift
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
        static let headerHorizontalPadding: CGFloat = 10
        static let searchDebounceNanoseconds: UInt64 = 180_000_000
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resultSummary: String {
        let matchCount = groups.reduce(0) { $0 + $1.matches.count }
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
            HelmSearchField(text: $query, placeholder: "Search", onSubmit: runSearch) {
                HStack(spacing: HelmSearchFieldMetrics.optionSpacing) {
                    SearchMatchOptionCluster(
                        caseSensitive: $caseSensitive,
                        matchWholeWord: $matchWholeWord
                    )
                    if !query.isEmpty {
                        clearButton
                    }
                }
            }
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

    private var clearButton: some View {
        Button(action: clearSearch) {
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
            SidebarEmptyPlaceholder(
                title: "Search in Project",
                subtitle: "Find text across files in \(project.name)."
            )
        } else if hasSearched, groups.isEmpty {
            SidebarEmptyPlaceholder(
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

    // MARK: - Search

    private func clearSearch() {
        query = ""
        groups = []
        hasSearched = false
    }

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
