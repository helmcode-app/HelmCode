//
//  SidebarSearchView.swift
//  HelmCode
//
//  Project-wide search navigator (Xcode / VS Code Find in Workspace).
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

    private var matchCount: Int {
        groups.reduce(0) { $0 + $1.matches.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider()
            resultsList
        }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onChange(of: caseSensitive) { _, _ in runSearch() }
        .onChange(of: matchWholeWord) { _, _ in runSearch() }
        .onChange(of: project.id) { _, _ in runSearch() }
    }

    // MARK: - Header

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                if !query.isEmpty {
                    Button {
                        query = ""
                        groups = []
                        hasSearched = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 12) {
                Toggle(isOn: $caseSensitive) {
                    Text("Aa")
                        .font(.caption.weight(.semibold).monospaced())
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Match Case")

                Toggle(isOn: $matchWholeWord) {
                    Text("W")
                        .font(.caption.weight(.semibold).monospaced())
                }
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Match Whole Word")

                Spacer(minLength: 0)

                if hasSearched, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(resultSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var resultSummary: String {
        if matchCount == 0 { return "No results" }
        let fileWord = groups.count == 1 ? "file" : "files"
        let matchWord = matchCount == 1 ? "result" : "results"
        return "\(matchCount) \(matchWord) in \(groups.count) \(fileWord)"
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsList: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            emptyState(
                title: "Search in Project",
                subtitle: "Find text across files in \(project.name)."
            )
        } else if hasSearched, groups.isEmpty {
            emptyState(
                title: "No Results",
                subtitle: "No matches for “\(trimmed)”."
            )
        } else {
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.matches) { match in
                            Button {
                                open(match)
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
            Image(systemName: fileSystemImage(group.languageHint))
                .foregroundStyle(fileIconColor(group.languageHint))
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

    // MARK: - Actions

    private func open(_ match: ProjectSearchMatch) {
        session.openFile(match.nodeID, revealLine: match.line)
    }

    private func scheduleSearch() {
        // Light debounce via main async; fine for sample workspace sizes.
        let snapshot = query
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard snapshot == query else { return }
            runSearch()
        }
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            groups = []
            hasSearched = false
            return
        }
        groups = ProjectSearch.search(
            project: project,
            query: trimmed,
            caseSensitive: caseSensitive,
            matchWholeWord: matchWholeWord
        )
        hasSearched = true
    }

    private func fileSystemImage(_ hint: String?) -> String {
        switch hint {
        case "swift": return "swift"
        case "ts", "js": return "curlybraces"
        case "json": return "curlybraces.square"
        case "md": return "doc.richtext"
        case "go": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.text"
        }
    }

    private func fileIconColor(_ hint: String?) -> Color {
        // Synthetic node for color helper.
        let node = WorkspaceNode(
            id: "tmp",
            name: "tmp",
            path: "tmp",
            isDirectory: false,
            children: [],
            languageHint: hint
        )
        return WorkspaceNodeIconStyle.color(for: node)
    }
}
