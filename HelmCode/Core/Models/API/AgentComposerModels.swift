//
//  AgentComposerModels.swift
//  HelmCode
//
//  Composer-facing types: mode, think level, and model catalog rows.
//  Timeline / phase types live in AgentModels.swift.
//

import Foundation

/// Interaction mode for the agent command bar.
enum AgentComposerMode: String, CaseIterable, Identifiable, Sendable {
    case agent
    case plan
    case ask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agent: return "Agent"
        case .plan: return "Plan"
        case .ask: return "Ask"
        }
    }

    var systemImage: String {
        switch self {
        case .agent: return "hammer.fill"
        case .plan: return "list.bullet"
        case .ask: return "bubble.left.and.bubble.right"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .agent: return "Describe a coding task for the agent…"
        case .plan: return "What should we plan before changing code?"
        case .ask: return "Ask about this codebase…"
        }
    }

    /// Modes the composer should offer. Ask is hidden unless the harness advertised it.
    static func available(advertised: [String]) -> [AgentComposerMode] {
        let ids = Set(advertised.map { $0.lowercased() })
        return allCases.filter { mode in
            switch mode {
            case .agent:
                return true
            case .plan:
                return ids.isEmpty || ids.contains("plan")
            case .ask:
                return ids.contains("ask")
            }
        }
    }
}

/// Reasoning effort sent with `/v1/sessions/:id/prompt`.
/// Prefer levels from `GET /v1/sessions/models.thinkLevels` (harness-advertised).
struct AgentThinkLevel: Identifiable, Hashable, Sendable {
    let rawValue: String

    var id: String { rawValue }

    var title: String {
        switch rawValue.lowercased() {
        case "low", "minimal", "min": return "Low"
        case "medium", "default", "normal": return "Medium"
        case "high": return "High"
        case "xhigh", "extra-high", "extrahigh", "max", "maximum": return "Extra High"
        case "true", "on", "yes", "1": return "On"
        case "false", "off", "no", "0": return "Off"
        case "none": return "None"
        default:
            // Context sizes (`200k`, `1m`) stay compact.
            if rawValue.range(of: #"^\d+[kKmM]?$"#, options: .regularExpression) != nil {
                return rawValue.lowercased()
            }
            return rawValue
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    static let low = AgentThinkLevel(rawValue: "low")
    static let medium = AgentThinkLevel(rawValue: "medium")
    static let high = AgentThinkLevel(rawValue: "high")
    static let xhigh = AgentThinkLevel(rawValue: "xhigh")

    static func fromWire(_ values: [String]?) -> [AgentThinkLevel] {
        let trimmed = (values ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var out: [AgentThinkLevel] = []
        for value in trimmed {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(AgentThinkLevel(rawValue: value))
        }
        return out
    }
}

/// Selectable model labels for the composer (`provider/model` for `/v1/sessions` prompt).
/// Prefer live catalog from `GET /v1/sessions/models` (current harness only).
struct AgentModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Provider display name (e.g. "OpenCode Go") — section headers / grouping.
    let subtitle: String

    /// Empty until the runner catalog loads — never invent OpenCode defaults.
    static let fallbackCatalog: [AgentModelOption] = []

    static let defaultID = ""

    /// Wire id shown under the title in lists (`opencode-go/glm-5.1`).
    var wireID: String { id }

    static func title(for id: String, in catalog: [AgentModelOption] = fallbackCatalog) -> String {
        catalog.first { $0.id == id }?.title ?? id
    }

    /// Strip Cursor-style `Name[context,effort/fast,…]` decorations.
    static func cleanLabel(_ raw: String) -> String {
        guard let bracket = raw.firstIndex(of: "[") else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(raw[..<bracket]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fromDTO(_ dto: SessionModelDTO) -> AgentModelOption {
        let id = cleanLabel(dto.id)
        let title = cleanLabel(dto.name.isEmpty ? id : dto.name)
        let displayTitle: String = {
            if let slash = title.lastIndex(of: "/"), slash < title.endIndex {
                let tail = String(title[title.index(after: slash)...])
                return tail.isEmpty ? title : tail
            }
            return title
        }()
        return AgentModelOption(
            id: id.isEmpty ? dto.id : id,
            title: displayTitle.isEmpty ? id : displayTitle,
            subtitle: dto.provider
        )
    }

    static func fromResponse(_ response: SessionModelsResponse) -> [AgentModelOption] {
        response.models.map(fromDTO)
    }

    /// Prefer the runner default, then the first catalog row (harness-agnostic).
    static func preferredDefaultID(
        in catalog: [AgentModelOption],
        serverDefault: String?
    ) -> String? {
        if let serverDefault, catalog.contains(where: { $0.id == serverDefault }) {
            return serverDefault
        }
        return catalog.first?.id
    }

    /// Group by provider name, sorted for Settings lists.
    static func groupedByProvider(
        _ models: [AgentModelOption]
    ) -> [(provider: String, models: [AgentModelOption])] {
        let groups = Dictionary(grouping: models, by: \.subtitle)
        return groups.keys.sorted().map { key in
            (
                provider: key,
                models: (groups[key] ?? []).sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            )
        }
    }

    static func matching(_ models: [AgentModelOption], query: String) -> [AgentModelOption] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return models }
        return models.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || $0.id.localizedCaseInsensitiveContains(q)
                || $0.subtitle.localizedCaseInsensitiveContains(q)
        }
    }
}
