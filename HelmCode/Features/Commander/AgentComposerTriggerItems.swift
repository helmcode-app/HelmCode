//
//  AgentComposerTriggerItems.swift
//  HelmCode
//
//  Picker rows for `/` (commands + skills) and `@` (workspace files).
//

import Foundation

enum AgentComposerTriggerItem: Identifiable, Equatable {
    case mode(AgentComposerMode)
    case skill(name: String, path: String)
    case file(WorkspaceNode)

    var id: String {
        switch self {
        case .mode(let mode):
            return "mode:\(mode.rawValue)"
        case .skill(_, let path):
            return "skill:\(path)"
        case .file(let node):
            return "file:\(node.id)"
        }
    }

    var title: String {
        switch self {
        case .mode(let mode):
            return mode.title
        case .skill(let name, _):
            return name
        case .file(let node):
            return node.name
        }
    }

    var subtitle: String {
        switch self {
        case .mode(let mode):
            return "/\(mode.rawValue)"
        case .skill(_, let path):
            return path
        case .file(let node):
            let dir = VFSPath.directory(of: node.path)
            return dir.isEmpty ? node.path : dir
        }
    }

    var systemImage: String? {
        switch self {
        case .mode(let mode):
            return mode.systemImage
        case .skill:
            return "sparkles"
        case .file:
            return nil
        }
    }

    /// Side effects on the engine, plus the prompt text that replaces `/query` or `@query`.
    func commit(into agent: AgentNetworkEngine) -> String {
        switch self {
        case .mode(let mode):
            agent.composerMode = mode
            return ""
        case .skill(let name, let path):
            agent.addContextPath(path)
            return "/\(name) "
        case .file(let node):
            agent.addContextPath(node.path)
            return AgentPromptTagging.fileTag(for: node.path) + " "
        }
    }
}

struct AgentComposerTriggerSection: Identifiable, Equatable {
    var id: String
    var header: String?
    var items: [AgentComposerTriggerItem]
}

enum AgentComposerTriggerCatalog {
    static let fileCap = 25

    static func sections(
        trigger: AgentComposerTrigger,
        project: WorkspaceProject?,
        selectedFileID: WorkspaceNode.ID?,
        modes: [AgentComposerMode]
    ) -> [AgentComposerTriggerSection] {
        switch trigger.kind {
        case .slash:
            return slashSections(query: trigger.query, project: project, modes: modes)
        case .mention:
            return [
                AgentComposerTriggerSection(
                    id: "files",
                    header: nil,
                    items: fileItems(
                        query: trigger.query,
                        project: project,
                        selectedFileID: selectedFileID
                    )
                )
            ]
        }
    }

    static func flattened(_ sections: [AgentComposerTriggerSection]) -> [AgentComposerTriggerItem] {
        sections.flatMap(\.items)
    }

    // MARK: - Slash

    private static func slashSections(
        query: String,
        project: WorkspaceProject?,
        modes: [AgentComposerMode]
    ) -> [AgentComposerTriggerSection] {
        let commands = modes.compactMap { mode -> AgentComposerTriggerItem? in
            let item = AgentComposerTriggerItem.mode(mode)
            return matches(item, query: query) ? item : nil
        }
        let skills = skillItems(in: project).filter { matches($0, query: query) }
        var sections: [AgentComposerTriggerSection] = []
        if !commands.isEmpty {
            sections.append(
                AgentComposerTriggerSection(id: "commands", header: "Commands", items: commands)
            )
        }
        sections.append(
            AgentComposerTriggerSection(id: "skills", header: "Skills", items: skills)
        )
        return sections
    }

    private static func skillItems(in project: WorkspaceProject?) -> [AgentComposerTriggerItem] {
        guard let root = project?.root else { return [] }
        return root.collectAllFiles(limit: 10_000).compactMap { node in
            guard node.name.compare("SKILL.md", options: .caseInsensitive) == .orderedSame else {
                return nil
            }
            let folder = VFSPath.directory(of: node.path)
            let name = folder.isEmpty ? "skill" : VFSPath.fileName(of: folder)
            return .skill(name: name, path: node.path)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Files

    private static func fileItems(
        query: String,
        project: WorkspaceProject?,
        selectedFileID: WorkspaceNode.ID?
    ) -> [AgentComposerTriggerItem] {
        guard let root = project?.root else { return [] }
        var files = root.collectAllFiles(limit: 10_000)
        if query.isEmpty, let selectedFileID,
           let idx = files.firstIndex(where: { $0.id == selectedFileID }) {
            let selected = files.remove(at: idx)
            files.insert(selected, at: 0)
        }
        let ranked = files.compactMap { node -> (Int, WorkspaceNode)? in
            let score = matchScore(name: node.name, path: node.path, query: query)
            guard score < 99 else { return nil }
            return (score, node)
        }
        .sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1.name.localizedCaseInsensitiveCompare(rhs.1.name) == .orderedAscending
        }
        return ranked.prefix(fileCap).map { .file($0.1) }
    }

    // MARK: - Matching

    private static func matches(_ item: AgentComposerTriggerItem, query: String) -> Bool {
        matchScore(name: item.title, path: item.subtitle, query: query) < 99
    }

    /// 0 exact · 1 prefix · 2 name contains · 3 path contains · 99 miss.
    private static func matchScore(name: String, path: String, query: String) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return 0 }
        let q = trimmed.lowercased()
        let n = name.lowercased()
        let p = path.lowercased()
        if n == q { return 0 }
        if n.hasPrefix(q) { return 1 }
        if n.contains(q) { return 2 }
        if p.contains(q) { return 3 }
        return 99
    }
}
