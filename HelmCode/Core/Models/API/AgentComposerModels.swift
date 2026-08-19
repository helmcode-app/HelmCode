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
enum AgentThinkLevel: String, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .xhigh: return "Extra High"
        }
    }
}

/// Selectable model labels for the composer (`provider/model` for `/v1/sessions` prompt).
/// Prefer live catalog from `GET /v1/sessions/models` (connected providers only).
struct AgentModelOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Provider display name (e.g. "OpenCode Go") — section headers / grouping.
    let subtitle: String

    /// Fallback when runner catalog is unavailable.
    static let fallbackCatalog: [AgentModelOption] = [
        .init(id: "opencode-go/glm-5.1", title: "glm-5.1", subtitle: "opencode-go"),
    ]

    static let defaultID = "opencode-go/glm-5.1"

    /// Wire id shown under the title in lists (`opencode-go/glm-5.1`).
    var wireID: String { id }

    static func title(for id: String, in catalog: [AgentModelOption] = fallbackCatalog) -> String {
        catalog.first { $0.id == id }?.title ?? id
    }

    static func fromDTO(_ dto: SessionModelDTO) -> AgentModelOption {
        AgentModelOption(id: dto.id, title: dto.name, subtitle: dto.provider)
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
